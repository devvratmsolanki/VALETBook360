import { useState, useEffect, useMemo } from 'react';
import { getUsers, updateUserRole, deleteUser } from '../../services/userService';
import { getCompanies } from '../../services/companyService';
import { useAuth } from '../../contexts/AuthContext';
import Card from '../../components/ui/Card';
import Badge from '../../components/ui/Badge';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import { toast } from '../../components/ui/Toast';
import {
    Users as UsersIcon, Search, Shield, Mail, Trash2, Building2,
    ChevronDown, ChevronRight, MapPin, Car, UserCog
} from 'lucide-react';

const ROLE_LABEL = { admin: 'Super Admin', company: 'Company', valet: 'Operator', driver: 'Driver' };
// Admin role is intentionally NOT in the assignable list. Promoting a user
// to admin must be done manually via the SQL editor — this prevents a
// compromised admin (or a UI bug) from minting more super admins.
const ROLE_ORDER = ['company', 'valet', 'driver'];
const ROLE_STYLE = {
    admin: 'bg-red-500/10 text-red-400 border-red-500/20',
    company: 'bg-blue-500/10 text-blue-400 border-blue-500/20',
    valet: 'bg-brand-500/10 text-brand-400 border-brand-500/20',
    driver: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
};
const ROLE_ICON = { admin: Shield, company: Building2, valet: UserCog, driver: Car };

const Users = () => {
    const { user: currentUser } = useAuth();
    const [users, setUsers] = useState([]);
    const [companies, setCompanies] = useState([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');
    const [collapsed, setCollapsed] = useState({}); // { [companyId]: true }

    const fetchAll = async () => {
        try {
            const [u, c] = await Promise.all([getUsers(), getCompanies()]);
            setUsers(u);
            setCompanies(c);
        } catch (err) {
            toast.error(err?.message || 'Failed to load users');
        } finally {
            setLoading(false);
        }
    };
    useEffect(() => { fetchAll(); }, []);

    const filteredUsers = useMemo(() => {
        if (!search) return users;
        const s = search.toLowerCase();
        return users.filter(u =>
            u.name?.toLowerCase().includes(s) ||
            u.email?.toLowerCase().includes(s) ||
            u.role?.toLowerCase().includes(s) ||
            u.valet_companies?.company_name?.toLowerCase().includes(s)
        );
    }, [search, users]);

    // Group: super admins (no company) + per-company groups
    const grouped = useMemo(() => {
        const admins = [];
        const byCompany = new Map();
        // seed every known company so empty companies still appear
        for (const c of companies) byCompany.set(c.id, { company: c, users: [] });

        for (const u of filteredUsers) {
            if (u.role === 'admin' && !u.valet_company_id) {
                admins.push(u);
                continue;
            }
            const cid = u.valet_company_id;
            if (!cid) {
                admins.push(u); // unaffiliated falls under admins/orphans bucket
                continue;
            }
            if (!byCompany.has(cid)) {
                byCompany.set(cid, {
                    company: u.valet_companies
                        ? { id: cid, company_name: u.valet_companies.company_name }
                        : { id: cid, company_name: 'Unknown Company' },
                    users: [],
                });
            }
            byCompany.get(cid).users.push(u);
        }
        return { admins, companyGroups: Array.from(byCompany.values()) };
    }, [filteredUsers, companies]);

    const handleRoleChange = async (id, newRole) => {
        try {
            await updateUserRole(id, newRole);
            toast.success('Role updated');
            fetchAll();
        } catch (err) {
            toast.error(err?.message || 'Update failed');
        }
    };

    const handleDelete = async (u) => {
        if (u.id === currentUser?.id) return toast.error("You can't delete your own account");
        if (!confirm(`Delete user "${u.name || u.email}"? This removes their profile row but the auth login may persist.`)) return;
        try {
            await deleteUser(u.id);
            toast.success('User deleted');
            fetchAll();
        } catch (err) {
            toast.error(err?.message || 'Delete failed');
        }
    };

    const toggleCompany = (id) => setCollapsed(s => ({ ...s, [id]: !s[id] }));

    const totalUsers = users.length;
    const adminCount = grouped.admins.length;
    const companyCount = grouped.companyGroups.length;

    return (
        <div className="animate-fade-in">
            <div className="flex flex-wrap items-end justify-between gap-3 mb-6">
                <div>
                    <h1 className="text-2xl font-bold text-white">Users</h1>
                    <p className="text-sm text-gray-500 mt-1">
                        {totalUsers} users · {adminCount} super admin{adminCount === 1 ? '' : 's'} · {companyCount} {companyCount === 1 ? 'company' : 'companies'}
                    </p>
                </div>
                <div className="relative">
                    <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500" />
                    <input
                        type="text"
                        value={search}
                        onChange={(e) => setSearch(e.target.value)}
                        placeholder="Search users or companies..."
                        className="block w-72 rounded-xl border-0 bg-dark-600 py-2.5 pl-10 pr-4 text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all"
                    />
                </div>
            </div>

            {loading ? (
                <div className="flex justify-center py-12"><LoadingSpinner size="md" /></div>
            ) : (
                <div className="space-y-6">
                    {/* Super Admins */}
                    <Section
                        title="Super Admins"
                        subtitle="Full system access — not bound to any company"
                        icon={Shield}
                        accent="text-red-400"
                        count={grouped.admins.length}
                    >
                        {grouped.admins.length === 0 ? (
                            <EmptyRow text="No super admins" />
                        ) : (
                            <UserTable
                                users={grouped.admins}
                                currentUserId={currentUser?.id}
                                onRoleChange={handleRoleChange}
                                onDelete={handleDelete}
                            />
                        )}
                    </Section>

                    {/* Companies */}
                    {grouped.companyGroups.length === 0 ? (
                        <Card className="p-8 text-center">
                            <Building2 className="h-8 w-8 text-gray-600 mx-auto mb-3" />
                            <p className="text-gray-500">No companies yet</p>
                        </Card>
                    ) : grouped.companyGroups.map(({ company, users }) => {
                        const isCollapsed = collapsed[company.id];
                        const buckets = groupByRole(users);
                        return (
                            <Card key={company.id} className="overflow-hidden">
                                <button
                                    onClick={() => toggleCompany(company.id)}
                                    className="w-full flex items-center justify-between px-5 py-4 hover:bg-white/[0.02] transition-colors"
                                >
                                    <div className="flex items-center gap-3">
                                        {isCollapsed ? <ChevronRight className="h-4 w-4 text-gray-500" /> : <ChevronDown className="h-4 w-4 text-gray-500" />}
                                        <div className="bg-brand-500/10 p-2 rounded-xl">
                                            <Building2 className="h-4 w-4 text-brand-400" />
                                        </div>
                                        <div className="text-left">
                                            <p className="font-semibold text-white">{company.company_name}</p>
                                            <p className="text-xs text-gray-500">
                                                {users.length} member{users.length === 1 ? '' : 's'} ·
                                                {' '}{buckets.company.length} company,
                                                {' '}{buckets.valet.length} operator{buckets.valet.length === 1 ? '' : 's'},
                                                {' '}{buckets.driver.length} driver{buckets.driver.length === 1 ? '' : 's'}
                                            </p>
                                        </div>
                                    </div>
                                </button>

                                {!isCollapsed && (
                                    <div className="border-t border-white/5 divide-y divide-white/5">
                                        <RoleBucket
                                            label="Company Owners"
                                            role="company"
                                            users={buckets.company}
                                            currentUserId={currentUser?.id}
                                            onRoleChange={handleRoleChange}
                                            onDelete={handleDelete}
                                        />
                                        <RoleBucket
                                            label="Operators"
                                            role="valet"
                                            users={buckets.valet}
                                            currentUserId={currentUser?.id}
                                            onRoleChange={handleRoleChange}
                                            onDelete={handleDelete}
                                        />
                                        <RoleBucket
                                            label="Drivers"
                                            role="driver"
                                            users={buckets.driver}
                                            currentUserId={currentUser?.id}
                                            onRoleChange={handleRoleChange}
                                            onDelete={handleDelete}
                                        />
                                    </div>
                                )}
                            </Card>
                        );
                    })}
                </div>
            )}
        </div>
    );
};

const groupByRole = (users) => {
    const out = { company: [], valet: [], driver: [], admin: [] };
    for (const u of users) (out[u.role] || (out[u.role] = [])).push(u);
    return out;
};

const Section = ({ title, subtitle, icon, accent, count, children }) => {
    const SectionIcon = icon;
    return (
    <Card className="overflow-hidden">
        <div className="px-5 py-4 border-b border-white/5 flex items-center gap-3">
            <SectionIcon className={`h-4 w-4 ${accent}`} />
            <div className="flex-1">
                <p className="font-semibold text-white">{title} <span className="text-xs text-gray-500 font-normal">({count})</span></p>
                {subtitle && <p className="text-xs text-gray-500">{subtitle}</p>}
            </div>
        </div>
        {children}
    </Card>
);
};

const RoleBucket = ({ label, role, users, currentUserId, onRoleChange, onDelete }) => {
    if (users.length === 0) return null;
    const BucketIcon = ROLE_ICON[role] || UsersIcon;
    return (
        <div>
            <div className="px-5 pt-3 pb-2 flex items-center gap-2">
                <BucketIcon className="h-3.5 w-3.5 text-gray-500" />
                <p className="text-xs uppercase tracking-wider text-gray-500 font-semibold">{label}</p>
                <span className="text-xs text-gray-600">({users.length})</span>
            </div>
            <UserTable users={users} currentUserId={currentUserId} onRoleChange={onRoleChange} onDelete={onDelete} />
        </div>
    );
};

const EmptyRow = ({ text }) => (
    <div className="px-5 py-6 text-center text-xs text-gray-500">{text}</div>
);

const UserTable = ({ users, currentUserId, onRoleChange, onDelete }) => (
    <div className="overflow-x-auto">
        <table className="w-full text-left text-sm">
            <thead className="bg-dark-700/30 text-[10px] uppercase text-gray-500">
                <tr>
                    <th className="px-5 py-2 font-medium">User</th>
                    <th className="px-5 py-2 font-medium">Email</th>
                    <th className="px-5 py-2 font-medium">Location</th>
                    <th className="px-5 py-2 font-medium">Role</th>
                    <th className="px-5 py-2 font-medium text-right">Actions</th>
                </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
                {users.map((u) => (
                    <tr key={u.id} className="hover:bg-white/[0.02] transition-colors">
                        <td className="px-5 py-3">
                            <div className="flex items-center gap-3">
                                <div className="h-7 w-7 rounded-full bg-gradient-to-br from-brand-400 to-brand-600 flex items-center justify-center text-black text-[10px] font-bold">
                                    {u.name?.charAt(0)?.toUpperCase() || '?'}
                                </div>
                                <p className="font-medium text-white text-sm">{u.name || 'N/A'}</p>
                            </div>
                        </td>
                        <td className="px-5 py-3 text-gray-400 text-xs">
                            <span className="inline-flex items-center gap-1"><Mail className="h-3 w-3" />{u.email || 'N/A'}</span>
                        </td>
                        <td className="px-5 py-3 text-gray-400 text-xs">
                            {u.location?.name ? (
                                <span className="inline-flex items-center gap-1"><MapPin className="h-3 w-3" />{u.location.name}</span>
                            ) : <span className="text-gray-600">—</span>}
                        </td>
                        <td className="px-5 py-3">
                            <div className="flex items-center gap-2">
                                <Badge className={ROLE_STYLE[u.role] || 'bg-gray-500/10 text-gray-400 border-gray-500/20'}>
                                    {ROLE_LABEL[u.role] || u.role}
                                </Badge>
                                <select
                                    value={u.role}
                                    onChange={(e) => onRoleChange(u.id, e.target.value)}
                                    className="bg-dark-600 text-gray-300 text-[11px] px-2 py-1 rounded-md ring-1 ring-white/5 focus:ring-brand-500/50 cursor-pointer"
                                >
                                    {ROLE_ORDER.map(r => <option key={r} value={r}>{ROLE_LABEL[r]}</option>)}
                                </select>
                            </div>
                        </td>
                        <td className="px-5 py-3 text-right">
                            {u.id !== currentUserId ? (
                                <button onClick={() => onDelete(u)} className="p-1.5 rounded-lg hover:bg-red-500/10 text-gray-600 hover:text-red-400 transition-colors" title="Delete user">
                                    <Trash2 className="h-4 w-4" />
                                </button>
                            ) : (
                                <span className="text-[10px] text-gray-600">You</span>
                            )}
                        </td>
                    </tr>
                ))}
            </tbody>
        </table>
    </div>
);

export default Users;
