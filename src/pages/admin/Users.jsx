import { useState, useEffect } from 'react';
import { getAllUsers, updateUserRole, deleteUser } from '../../services/userService';
import { useAuth } from '../../contexts/AuthContext';
import Card from '../../components/ui/Card';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import { toast } from '../../components/ui/Toast';
import { Users as UsersIcon, Search, Shield, Mail, Trash2 } from 'lucide-react';

const Users = () => {
    const { user: currentUser } = useAuth();
    const [users, setUsers] = useState([]);
    const [filtered, setFiltered] = useState([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');

    const fetchUsers = async () => { try { const d = await getAllUsers(); setUsers(d); setFiltered(d); } catch { toast.error('Failed to load'); } finally { setLoading(false); } };
    useEffect(() => { fetchUsers(); }, []);
    useEffect(() => { if (!search) { setFiltered(users); return; } const s = search.toLowerCase(); setFiltered(users.filter(u => u.name?.toLowerCase().includes(s) || u.email?.toLowerCase().includes(s) || u.role?.toLowerCase().includes(s))); }, [search, users]);

    const handleRoleChange = async (id, newRole) => { try { await updateUserRole(id, newRole); toast.success('Role updated'); fetchUsers(); } catch { toast.error('Update failed'); } };
    const handleDelete = async (u) => {
        if (u.id === currentUser?.id) return toast.error("You can't delete your own account");
        if (!confirm(`Delete user "${u.name || u.email}"? This cannot be undone.`)) return;
        try { await deleteUser(u.id); toast.success('User deleted'); fetchUsers(); } catch { toast.error('Delete failed'); }
    };
    const roles = ['admin', 'company', 'valet'];
    const getRoleStyle = (r) => ({ admin: 'bg-red-500/10 text-red-400 border-red-500/20', company: 'bg-blue-500/10 text-blue-400 border-blue-500/20', valet: 'bg-brand-500/10 text-brand-400 border-brand-500/20' }[r] || '');

    return (
        <div className="animate-fade-in">
            <div className="flex items-center justify-between mb-6"><div><h1 className="text-2xl font-bold text-white">Users</h1><p className="text-sm text-gray-500 mt-1">{users.length} total users</p></div></div>
            <div className="mb-6"><div className="relative"><Search className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500" /><input type="text" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search users..." className="block w-full max-w-md rounded-xl border-0 bg-dark-600 py-2.5 pl-10 pr-4 text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all" /></div></div>
            {loading ? <div className="flex justify-center py-12"><div className="animate-spin h-6 w-6 border-2 border-brand-500 border-t-transparent rounded-full" /></div> : filtered.length === 0 ? <Card className="p-8 text-center"><UsersIcon className="h-8 w-8 text-gray-600 mx-auto mb-3" /><p className="text-gray-500">No users found</p></Card> : (
                <Card className="overflow-hidden"><div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="bg-dark-700/50 text-xs uppercase text-gray-500"><tr><th className="px-6 py-3">User</th><th className="px-6 py-3">Email</th><th className="px-6 py-3">Company</th><th className="px-6 py-3">Role</th><th className="px-6 py-3">Actions</th></tr></thead><tbody className="divide-y divide-white/5">{filtered.map((u) => (<tr key={u.id} className="hover:bg-white/[0.02] transition-colors"><td className="px-6 py-4"><div className="flex items-center gap-3"><div className="h-8 w-8 rounded-full bg-gradient-to-br from-brand-400 to-brand-600 flex items-center justify-center text-black text-xs font-bold">{u.name?.charAt(0)?.toUpperCase() || '?'}</div><p className="font-medium text-white text-sm">{u.name || 'N/A'}</p></div></td><td className="px-6 py-4 text-gray-400 text-xs flex items-center gap-1"><Mail className="h-3 w-3" />{u.email || 'N/A'}</td><td className="px-6 py-4 text-gray-400 text-sm">{u.valet_companies?.company_name || '-'}</td><td className="px-6 py-4"><select value={u.role} onChange={(e) => handleRoleChange(u.id, e.target.value)} className="appearance-none bg-dark-600 text-gray-300 text-xs px-3 py-1.5 rounded-lg ring-1 ring-white/5 focus:ring-brand-500/50 cursor-pointer">{roles.map(r => <option key={r} value={r}>{r.replace('_', ' ')}</option>)}</select></td><td className="px-6 py-4">{u.id !== currentUser?.id ? (<button onClick={() => handleDelete(u)} className="p-1.5 rounded-lg hover:bg-red-500/10 text-gray-600 hover:text-red-400 transition-colors" title="Delete user"><Trash2 className="h-4 w-4" /></button>) : (<span className="text-[10px] text-gray-600">You</span>)}</td></tr>))}</tbody></table></div></Card>
            )}
        </div>
    );
};

export default Users;

