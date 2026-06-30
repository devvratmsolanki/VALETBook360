import { useState, useEffect, useMemo } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import { getLocationsByCompany, deleteLocation } from '../../services/locationService';
import { getDriversByCompany, deleteDriver, toggleDriverActive, updateDriver } from '../../services/driverService';
import { getUsersByCompany, deleteUser, updateUser, toggleUserActive } from '../../services/userService';
import { syncSlotsWithCapacity } from '../../services/slotService';
import { createLocation } from '../../services/locationService';
import { createStaff } from '../../services/userService';
import { createDriver } from '../../services/driverService';
import { isValidEmail, isValidPassword, isValidPhone, normalizePhone, formatDate } from '../../lib/utils';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Modal from '../../components/ui/Modal';
import Input from '../../components/ui/Input';
import Badge from '../../components/ui/Badge';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import { toast } from '../../components/ui/Toast';
import logger from '../../lib/logger';
import {
    ArrowLeft, Building2, MapPin, Users, Car, Plus, Trash2,
    Phone, Mail, Key, Eye, EyeOff, Shield, Edit2, ToggleLeft, ToggleRight
} from 'lucide-react';

const TABS = [
    { key: 'overview', label: 'Overview', icon: Building2 },
    { key: 'locations', label: 'Locations', icon: MapPin },
    { key: 'operators', label: 'Operators', icon: Users },
    { key: 'drivers', label: 'Drivers', icon: Car },
];

const CompanyDetail = () => {
    const { id: companyId } = useParams();
    const navigate = useNavigate();
    const [company, setCompany] = useState(null);
    const [tab, setTab] = useState('overview');
    const [loading, setLoading] = useState(true);
    const [locations, setLocations] = useState([]);
    const [staff, setStaff] = useState([]);
    const [drivers, setDrivers] = useState([]);

    const fetchAll = async () => {
        try {
            const [cRes, l, s, d] = await Promise.all([
                supabase.from('valet_companies').select('*').eq('id', companyId).maybeSingle(),
                getLocationsByCompany(companyId),
                getUsersByCompany(companyId),
                getDriversByCompany(companyId),
            ]);
            if (cRes.error) throw cRes.error;
            setCompany(cRes.data);
            setLocations(l);
            setStaff(s);
            setDrivers(d);
        } catch (err) {
            logger.error(err);
            toast.error(err?.message || 'Failed to load company');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => { fetchAll(); }, [companyId]);

    const operators = useMemo(() => staff.filter(u => u.role === 'valet'), [staff]);
    const owners = useMemo(() => staff.filter(u => u.role === 'company'), [staff]);

    if (loading) return <div className="flex items-center justify-center h-64"><LoadingSpinner size="lg" /></div>;
    if (!company) return (
        <Card className="p-8 text-center">
            <Building2 className="h-8 w-8 text-gray-600 mx-auto mb-3" />
            <p className="text-gray-500">Company not found</p>
            <Button className="mt-4" onClick={() => navigate('/admin/companies')}>Back to Companies</Button>
        </Card>
    );

    return (
        <div className="animate-fade-in">
            <button onClick={() => navigate('/admin/companies')} className="flex items-center gap-2 text-xs text-gray-500 hover:text-brand-400 mb-3 transition-colors">
                <ArrowLeft className="h-3.5 w-3.5" /> All companies
            </button>

            <div className="flex items-start justify-between mb-6 flex-wrap gap-3">
                <div className="flex items-center gap-3">
                    <div className="bg-brand-500/10 p-3 rounded-xl">
                        <Building2 className="h-6 w-6 text-brand-400" />
                    </div>
                    <div>
                        <h1 className="text-2xl font-bold text-white">{company.company_name}</h1>
                        <p className="text-sm text-gray-500 mt-0.5">
                            {company.owner_name && <span>Owner: {company.owner_name}</span>}
                            {company.email && <span> · {company.email}</span>}
                            {company.phone && <span> · {company.phone}</span>}
                        </p>
                    </div>
                </div>
                <div className="flex gap-2">
                    <Badge className="bg-brand-500/10 text-brand-400 border-brand-500/20">{locations.length} locations</Badge>
                    <Badge className="bg-purple-500/10 text-purple-400 border-purple-500/20">{operators.length} operators</Badge>
                    <Badge className="bg-emerald-500/10 text-emerald-400 border-emerald-500/20">{drivers.length} drivers</Badge>
                </div>
            </div>

            <div className="flex gap-1 mb-6 bg-dark-800/40 p-1 rounded-xl border border-white/5 overflow-x-auto">
                {TABS.map(t => {
                    const Icon = t.icon;
                    return (
                        <button
                            key={t.key}
                            onClick={() => setTab(t.key)}
                            className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium whitespace-nowrap transition-all ${tab === t.key
                                ? 'bg-brand-500/10 text-brand-400 border border-brand-500/20'
                                : 'text-gray-400 hover:text-white border border-transparent'
                                }`}
                        >
                            <Icon className="h-4 w-4" /> {t.label}
                        </button>
                    );
                })}
            </div>

            {tab === 'overview' && (
                <Overview company={company} locations={locations} operators={operators} drivers={drivers} owners={owners} />
            )}
            {tab === 'locations' && (
                <LocationsTab companyId={companyId} locations={locations} onRefresh={fetchAll} />
            )}
            {tab === 'operators' && (
                <OperatorsTab companyId={companyId} operators={operators} locations={locations} onRefresh={fetchAll} />
            )}
            {tab === 'drivers' && (
                <DriversTab companyId={companyId} drivers={drivers} locations={locations} onRefresh={fetchAll} />
            )}
        </div>
    );
};

// ─── Overview ───
const Overview = ({ company, locations, operators, drivers, owners }) => (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <Card className="p-5">
            <p className="text-xs text-gray-500 uppercase tracking-wider mb-3">Company Details</p>
            <div className="space-y-2 text-sm">
                <Row label="Name" value={company.company_name} />
                <Row label="Owner" value={company.owner_name || '—'} />
                <Row label="Email" value={company.email || '—'} />
                <Row label="Phone" value={company.phone || '—'} />
                <Row label="Created" value={formatDate(company.created_at)} />
            </div>
        </Card>
        <Card className="p-5">
            <p className="text-xs text-gray-500 uppercase tracking-wider mb-3">Quick Stats</p>
            <div className="grid grid-cols-2 gap-3">
                <Stat icon={MapPin} label="Locations" value={locations.length} accent="text-brand-400" />
                <Stat icon={Shield} label="Owners" value={owners.length} accent="text-blue-400" />
                <Stat icon={Users} label="Operators" value={operators.length} accent="text-purple-400" />
                <Stat icon={Car} label="Drivers" value={drivers.length} accent="text-emerald-400" />
            </div>
        </Card>
    </div>
);

const Row = ({ label, value }) => (
    <div className="flex justify-between gap-3">
        <span className="text-gray-500">{label}</span>
        <span className="text-gray-200 text-right break-all">{value}</span>
    </div>
);

const Stat = ({ icon, label, value, accent }) => {
    const IconComponent = icon;
    return (
        <div className="p-3 rounded-xl bg-dark-700/30 border border-white/5">
            <div className="flex items-center gap-2 text-gray-400 text-xs">
                <IconComponent className={`h-3.5 w-3.5 ${accent}`} /> {label}
            </div>
            <p className="text-xl font-bold text-white mt-1">{value}</p>
        </div>
    );
};

// ─── Locations Tab ───
const LocationsTab = ({ companyId, locations, onRefresh }) => {
    const [showModal, setShowModal] = useState(false);
    const [formData, setFormData] = useState({ name: '', address: '', city: '', state: '', country: '', key_capacity: 0 });
    const [saving, setSaving] = useState(false);

    const handleCreate = async (e) => {
        e.preventDefault();
        if (!formData.name.trim() || formData.name.trim().length < 2) return toast.error('Name must be at least 2 characters');
        setSaving(true);
        try {
            const capacity = parseInt(formData.key_capacity) || 0;
            const loc = await createLocation({ ...formData, valet_company_id: companyId, key_capacity: capacity });
            if (capacity > 0) await syncSlotsWithCapacity(loc.id, capacity);
            toast.success('Location added');
            setShowModal(false);
            setFormData({ name: '', address: '', city: '', state: '', country: '', key_capacity: 0 });
            onRefresh();
        } catch (err) {
            toast.error(err.message || 'Failed');
        } finally {
            setSaving(false);
        }
    };

    const handleDelete = async (loc) => {
        if (!confirm(`Delete location "${loc.name}"?`)) return;
        try {
            await deleteLocation(loc.id);
            toast.success('Deleted');
            onRefresh();
        } catch (err) {
            toast.error(err?.message || 'Failed to delete');
        }
    };

    return (
        <div>
            <div className="flex justify-between items-center mb-4">
                <p className="text-sm text-gray-400">{locations.length} location{locations.length === 1 ? '' : 's'} in this company</p>
                <Button onClick={() => setShowModal(true)}><Plus className="h-4 w-4" /> Add Location</Button>
            </div>

            {locations.length === 0 ? (
                <Card className="p-8 text-center">
                    <MapPin className="h-8 w-8 text-gray-600 mx-auto mb-3" />
                    <p className="text-gray-500">No locations yet</p>
                </Card>
            ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                    {locations.map(loc => (
                        <Card key={loc.id} className="p-4">
                            <div className="flex items-start justify-between">
                                <div className="flex items-start gap-3 min-w-0">
                                    <div className="bg-brand-500/10 p-2 rounded-xl shrink-0">
                                        <MapPin className="h-4 w-4 text-brand-400" />
                                    </div>
                                    <div className="min-w-0">
                                        <p className="font-medium text-white text-sm truncate">{loc.name}</p>
                                        {loc.address && <p className="text-xs text-gray-500 mt-0.5 truncate">{loc.address}</p>}
                                        <p className="text-xs text-gray-600 truncate">{[loc.city, loc.state].filter(Boolean).join(', ') || '—'}</p>
                                        <span className="inline-block mt-2 text-[10px] bg-brand-500/10 px-1.5 py-0.5 rounded text-brand-400 border border-brand-500/10">
                                            🔑 {loc.key_capacity || 0} slots
                                        </span>
                                    </div>
                                </div>
                                <button onClick={() => handleDelete(loc)} className="p-1.5 rounded-lg hover:bg-red-500/10 text-gray-600 hover:text-red-400 transition-colors shrink-0">
                                    <Trash2 className="h-3.5 w-3.5" />
                                </button>
                            </div>
                        </Card>
                    ))}
                </div>
            )}

            <Modal isOpen={showModal} onClose={() => setShowModal(false)} title="Add Location">
                <form onSubmit={handleCreate} className="space-y-4">
                    <Input label="Name" required value={formData.name} onChange={(e) => setFormData({ ...formData, name: e.target.value })} placeholder="Location name" />
                    <Input label="Address" value={formData.address} onChange={(e) => setFormData({ ...formData, address: e.target.value })} placeholder="Street address" />
                    <div className="grid grid-cols-2 gap-3">
                        <Input label="City" value={formData.city} onChange={(e) => setFormData({ ...formData, city: e.target.value })} placeholder="City" />
                        <Input label="State" value={formData.state} onChange={(e) => setFormData({ ...formData, state: e.target.value })} placeholder="State" />
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                        <Input label="Country" value={formData.country} onChange={(e) => setFormData({ ...formData, country: e.target.value })} placeholder="Country" />
                        <Input label="Key Slots" type="number" min="0" value={formData.key_capacity} onChange={(e) => setFormData({ ...formData, key_capacity: e.target.value })} placeholder="e.g. 50" />
                    </div>
                    <div className="flex justify-end gap-3 pt-2">
                        <Button variant="ghost" type="button" onClick={() => setShowModal(false)}>Cancel</Button>
                        <Button type="submit" disabled={saving}>{saving ? 'Adding...' : 'Add Location'}</Button>
                    </div>
                </form>
            </Modal>
        </div>
    );
};

// ─── Operators Tab ───
const OperatorsTab = ({ companyId, operators, locations, onRefresh }) => {
    const [showModal, setShowModal] = useState(false);
    const [form, setForm] = useState({ name: '', email: '', password: '', location_id: '' });
    const [showPwd, setShowPwd] = useState(false);
    const [saving, setSaving] = useState(false);
    const [togglingId, setTogglingId] = useState(null);

    const [editModal, setEditModal] = useState(false);
    const [editForm, setEditForm] = useState({ id: null, name: '', location_id: '' });
    const [savingEdit, setSavingEdit] = useState(false);

    const handleToggleOperator = async (o) => {
        setTogglingId(o.id);
        try {
            await toggleUserActive(o.id, !o.is_active);
            toast.success(o.is_active ? `${o.name || 'Operator'} disabled` : `${o.name || 'Operator'} enabled`);
            onRefresh();
        } catch (err) {
            toast.error(err?.message || 'Failed to update status');
        } finally {
            setTogglingId(null);
        }
    };

    const startEdit = (o) => {
        setEditForm({ id: o.id, name: o.name || '', location_id: o.location_id || '' });
        setEditModal(true);
    };

    const handleEdit = async (e) => {
        e.preventDefault();
        if (!editForm.name.trim() || editForm.name.trim().length < 2) return toast.error('Name too short');
        setSavingEdit(true);
        try {
            await updateUser(editForm.id, { name: editForm.name.trim(), location_id: editForm.location_id || null });
            toast.success('Operator updated');
            setEditModal(false);
            onRefresh();
        } catch (err) {
            toast.error(err.userMessage || err.message);
        } finally {
            setSavingEdit(false);
        }
    };

    const handleCreate = async (e) => {
        e.preventDefault();
        if (!form.name.trim() || form.name.trim().length < 2) return toast.error('Name too short');
        if (!isValidEmail(form.email)) return toast.error('Invalid email');
        if (!isValidPassword(form.password)) return toast.error('Password: 8+ chars with a letter and a number');
        setSaving(true);
        try {
            await createStaff({
                email: form.email.trim().toLowerCase(),
                password: form.password,
                name: form.name.trim(),
                role: 'valet',
                company_id: companyId,
                location_id: form.location_id || null,
            });
            toast.success('Operator created');
            setShowModal(false);
            setForm({ name: '', email: '', password: '', location_id: '' });
            onRefresh();
        } catch (err) {
            toast.error(err.message || 'Failed');
        } finally {
            setSaving(false);
        }
    };

    const handleDelete = async (u) => {
        if (!confirm(`Remove operator "${u.name || u.email}"?`)) return;
        try {
            await deleteUser(u.id);
            toast.success('Removed');
            onRefresh();
        } catch (err) {
            toast.error(err?.message || 'Failed to remove operator');
        }
    };

    return (
        <div>
            <div className="flex justify-between items-center mb-4">
                <p className="text-sm text-gray-400">{operators.length} operator{operators.length === 1 ? '' : 's'}</p>
                <Button onClick={() => setShowModal(true)}><Plus className="h-4 w-4" /> Add Operator</Button>
            </div>
            {operators.length === 0 ? (
                <Card className="p-8 text-center">
                    <Users className="h-8 w-8 text-gray-600 mx-auto mb-3" />
                    <p className="text-gray-500">No operators yet</p>
                </Card>
            ) : (
                <Card className="overflow-hidden">
                    <table className="w-full text-left text-sm">
                        <thead className="bg-dark-700/40 text-[10px] uppercase text-gray-500">
                            <tr>
                                <th className="px-5 py-2 font-medium">Name</th>
                                <th className="px-5 py-2 font-medium">Email</th>
                                <th className="px-5 py-2 font-medium">Location</th>
                                <th className="px-5 py-2 font-medium">Status</th>
                                <th className="px-5 py-2 font-medium text-right">Actions</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-white/5">
                            {operators.map(o => {
                                const isActive = o.is_active !== false;
                                const isToggling = togglingId === o.id;
                                return (
                                    <tr key={o.id} className={`hover:bg-white/[0.02] transition-opacity ${!isActive ? 'opacity-60' : ''}`}>
                                        <td className="px-5 py-3 text-white">{o.name || 'N/A'}</td>
                                        <td className="px-5 py-3 text-gray-400 text-xs"><span className="inline-flex items-center gap-1"><Mail className="h-3 w-3" />{o.email}</span></td>
                                        <td className="px-5 py-3 text-gray-400 text-xs">{o.location?.name || <span className="text-gray-600">—</span>}</td>
                                        <td className="px-5 py-3">
                                            <span className={`inline-flex items-center gap-1 text-[10px] font-medium px-2 py-0.5 rounded-full border ${
                                                isActive
                                                    ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20'
                                                    : 'bg-gray-500/10 text-gray-500 border-gray-500/20'
                                            }`}>
                                                <span className={`h-1.5 w-1.5 rounded-full ${isActive ? 'bg-emerald-400' : 'bg-gray-500'}`} />
                                                {isActive ? 'Active' : 'Disabled'}
                                            </span>
                                        </td>
                                        <td className="px-5 py-3 text-right">
                                            <div className="flex justify-end gap-1">
                                                <button
                                                    onClick={() => startEdit(o)}
                                                    aria-label="Edit operator"
                                                    className="p-1.5 rounded-lg hover:bg-white/5 text-gray-600 hover:text-white transition-colors"
                                                >
                                                    <Edit2 className="h-4 w-4" />
                                                </button>
                                                <button
                                                    onClick={() => handleToggleOperator(o)}
                                                    disabled={isToggling}
                                                    aria-label={isActive ? 'Disable operator' : 'Enable operator'}
                                                    title={isActive ? 'Disable' : 'Enable'}
                                                    className={`p-1.5 rounded-lg transition-colors ${
                                                        isActive
                                                            ? 'hover:bg-orange-500/10 text-gray-600 hover:text-orange-400'
                                                            : 'hover:bg-emerald-500/10 text-gray-600 hover:text-emerald-400'
                                                    } ${isToggling ? 'opacity-50 cursor-not-allowed' : ''}`}
                                                >
                                                    {isActive
                                                        ? <ToggleRight className="h-4 w-4" />
                                                        : <ToggleLeft className="h-4 w-4" />}
                                                </button>
                                                <button
                                                    onClick={() => handleDelete(o)}
                                                    aria-label="Remove operator"
                                                    className="p-1.5 rounded-lg hover:bg-red-500/10 text-gray-600 hover:text-red-400 transition-colors"
                                                >
                                                    <Trash2 className="h-4 w-4" />
                                                </button>
                                            </div>
                                        </td>
                                    </tr>
                                );
                            })}
                        </tbody>
                    </table>
                </Card>
            )}

            <Modal isOpen={showModal} onClose={() => setShowModal(false)} title="Add Operator">
                <form onSubmit={handleCreate} className="space-y-4">
                    <Input label="Name" required value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Operator name" />
                    <Input icon={Mail} label="Email" type="email" required value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} placeholder="operator@example.com" autoComplete="off" />
                    <PasswordInline value={form.password} onChange={(v) => setForm({ ...form, password: v })} show={showPwd} onToggle={() => setShowPwd(s => !s)} />
                    {locations.length > 0 && (
                        <div className="space-y-1.5">
                            <label className="block text-sm font-medium text-gray-300">Assigned Location</label>
                            <select
                                value={form.location_id}
                                onChange={(e) => setForm({ ...form, location_id: e.target.value })}
                                className="block w-full rounded-xl border-0 bg-dark-600 py-3 px-4 text-gray-200 ring-1 ring-inset ring-white/5 focus:ring-2 focus:ring-brand-500/50 text-sm transition-all"
                            >
                                <option value="">No location (floating)</option>
                                {locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}
                            </select>
                        </div>
                    )}
                    <div className="flex justify-end gap-3 pt-2">
                        <Button variant="ghost" type="button" onClick={() => setShowModal(false)}>Cancel</Button>
                        <Button type="submit" disabled={saving}>{saving ? 'Creating...' : 'Create Operator'}</Button>
                    </div>
                </form>
            </Modal>

            <Modal isOpen={editModal} onClose={() => setEditModal(false)} title="Edit Operator">
                <form onSubmit={handleEdit} className="space-y-4">
                    <Input label="Name" required value={editForm.name} onChange={(e) => setEditForm({ ...editForm, name: e.target.value })} placeholder="Operator name" />
                    {locations.length > 0 && (
                        <div className="space-y-1.5">
                            <label className="block text-sm font-medium text-gray-300">Assigned Location</label>
                            <select
                                value={editForm.location_id}
                                onChange={(e) => setEditForm({ ...editForm, location_id: e.target.value })}
                                className="block w-full rounded-xl border-0 bg-dark-600 py-3 px-4 text-gray-200 ring-1 ring-inset ring-white/5 focus:ring-2 focus:ring-brand-500/50 text-sm transition-all"
                            >
                                <option value="">Unassigned</option>
                                {locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}
                            </select>
                        </div>
                    )}
                    <div className="flex justify-end gap-3 pt-2">
                        <Button variant="ghost" type="button" onClick={() => setEditModal(false)}>Cancel</Button>
                        <Button type="submit" disabled={savingEdit}>{savingEdit ? 'Saving...' : 'Save Changes'}</Button>
                    </div>
                </form>
            </Modal>
        </div>
    );
};

// ─── Drivers Tab ───
const DriversTab = ({ companyId, drivers, locations, onRefresh }) => {
    const [showModal, setShowModal] = useState(false);
    const [form, setForm] = useState({
        name: '', phone: '', license_number: '', staff_id: '',
        create_login: true, email: '', password: '', location_id: '',
    });
    const [showPwd, setShowPwd] = useState(false);
    const [saving, setSaving] = useState(false);

    const [editModal, setEditModal] = useState(false);
    const [editForm, setEditForm] = useState({ id: null, name: '', phone: '', location_id: '' });
    const [savingEdit, setSavingEdit] = useState(false);

    const startEdit = (d) => {
        setEditForm({ id: d.id, name: d.name || '', phone: d.phone || '', location_id: d.location_id || '' });
        setEditModal(true);
    };

    const handleEdit = async (e) => {
        e.preventDefault();
        if (!editForm.name.trim() || editForm.name.trim().length < 2) return toast.error('Name too short');
        if (!isValidPhone(editForm.phone)) return toast.error('Invalid phone (7–15 digits)');
        setSavingEdit(true);
        try {
            await updateDriver(editForm.id, {
                name: editForm.name.trim(),
                phone: normalizePhone(editForm.phone),
                location_id: editForm.location_id || null,
            });
            toast.success('Driver updated');
            setEditModal(false);
            onRefresh();
        } catch (err) {
            toast.error(err.userMessage || err.message);
        } finally {
            setSavingEdit(false);
        }
    };

    const handleCreate = async (e) => {
        e.preventDefault();
        if (!form.name.trim() || form.name.trim().length < 2) return toast.error('Name too short');
        if (!isValidPhone(form.phone)) return toast.error('Invalid phone (7–15 digits)');
        if (form.create_login) {
            if (!isValidEmail(form.email)) return toast.error('Invalid email');
            if (!isValidPassword(form.password)) return toast.error('Password: 8+ chars with a letter and a number');
        }
        setSaving(true);
        try {
            let userId = null;
            if (form.create_login) {
                const result = await createStaff({
                    email: form.email.trim().toLowerCase(),
                    password: form.password,
                    name: form.name.trim(),
                    role: 'driver',
                    company_id: companyId,
                    location_id: form.location_id || null,
                });
                userId = result?.user?.id || null;
            }
            await createDriver({
                valet_company_id: companyId,
                name: form.name.trim(),
                phone: normalizePhone(form.phone),
                license_number: form.license_number.trim() || null,
                staff_id: form.staff_id.trim() || null,
                location_id: form.location_id || null,
                user_id: userId,
                email: form.create_login ? form.email.trim().toLowerCase() : null,
                active: true,
            });
            toast.success('Driver added');
            setShowModal(false);
            setForm({ name: '', phone: '', license_number: '', staff_id: '', create_login: true, email: '', password: '', location_id: '' });
            onRefresh();
        } catch (err) {
            toast.error(err.message || 'Failed');
        } finally {
            setSaving(false);
        }
    };

    const handleToggle = async (d) => {
        try {
            await toggleDriverActive(d.id, !d.active);
            onRefresh();
        } catch (err) {
            toast.error(err?.message || 'Failed to toggle driver');
        }
    };

    const handleDelete = async (d) => {
        const msg = d.user_id
            ? `Delete driver "${d.name}"? This also removes their login.`
            : `Delete driver "${d.name}"?`;
        if (!confirm(msg)) return;
        try {
            await deleteDriver(d.id);
            toast.success('Driver deleted');
            onRefresh();
        } catch (err) {
            toast.error(err.message || 'Failed');
        }
    };

    return (
        <div>
            <div className="flex justify-between items-center mb-4">
                <p className="text-sm text-gray-400">{drivers.length} driver{drivers.length === 1 ? '' : 's'}</p>
                <Button onClick={() => setShowModal(true)}><Plus className="h-4 w-4" /> Add Driver</Button>
            </div>
            {drivers.length === 0 ? (
                <Card className="p-8 text-center">
                    <Car className="h-8 w-8 text-gray-600 mx-auto mb-3" />
                    <p className="text-gray-500">No drivers yet</p>
                </Card>
            ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                    {drivers.map(d => (
                        <Card key={d.id} className={`p-4 transition-opacity ${!d.active ? 'opacity-60' : ''}`}>
                            <div className="flex items-start justify-between">
                                <div className="flex items-center gap-3 min-w-0">
                                    <div className={`h-10 w-10 rounded-full flex items-center justify-center text-sm font-bold shrink-0 ${d.active ? 'bg-emerald-500/10 text-emerald-400' : 'bg-gray-500/10 text-gray-500'}`}>
                                        {d.name?.charAt(0)?.toUpperCase() || '?'}
                                    </div>
                                    <div className="min-w-0">
                                        <p className="font-medium text-white text-sm truncate">{d.name}</p>
                                        <p className="text-xs text-gray-500 flex items-center gap-1 mt-0.5"><Phone className="h-3 w-3" />{d.phone || 'N/A'}</p>
                                        <div className="flex items-center gap-2 mt-1">
                                            <span className={`inline-flex items-center gap-1 text-[10px] font-medium px-1.5 py-0.5 rounded-full border ${
                                                d.active
                                                    ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20'
                                                    : 'bg-gray-500/10 text-gray-500 border-gray-500/20'
                                            }`}>
                                                <span className={`h-1.5 w-1.5 rounded-full ${d.active ? 'bg-emerald-400' : 'bg-gray-500'}`} />
                                                {d.active ? 'Active' : 'Disabled'}
                                            </span>
                                            {d.user_id && <span className="text-[10px] text-emerald-400/80 flex items-center gap-1"><Key className="h-3 w-3" />Login</span>}
                                        </div>
                                    </div>
                                </div>
                                <div className="flex items-center gap-1 shrink-0">
                                    <button onClick={() => startEdit(d)} aria-label="Edit driver" className="p-1.5 rounded-lg hover:bg-white/5 text-gray-500 hover:text-white" title="Edit">
                                        <Edit2 className="h-3.5 w-3.5" />
                                    </button>
                                    <button
                                        onClick={() => handleToggle(d)}
                                        aria-label={d.active ? 'Disable driver' : 'Enable driver'}
                                        title={d.active ? 'Disable' : 'Enable'}
                                        className={`p-1.5 rounded-lg transition-colors ${
                                            d.active
                                                ? 'hover:bg-orange-500/10 text-gray-500 hover:text-orange-400'
                                                : 'hover:bg-emerald-500/10 text-gray-500 hover:text-emerald-400'
                                        }`}
                                    >
                                        {d.active ? <ToggleRight className="h-3.5 w-3.5" /> : <ToggleLeft className="h-3.5 w-3.5" />}
                                    </button>
                                    <button onClick={() => handleDelete(d)} className="p-1.5 rounded-lg hover:bg-red-500/10 text-gray-600 hover:text-red-400" title="Delete">
                                        <Trash2 className="h-3.5 w-3.5" />
                                    </button>
                                </div>
                            </div>
                        </Card>
                    ))}
                </div>
            )}

            <Modal isOpen={showModal} onClose={() => setShowModal(false)} title="Add Driver">
                <form onSubmit={handleCreate} className="space-y-4">
                    <div className="grid grid-cols-2 gap-3">
                        <Input label="Name" required value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
                        <Input icon={Phone} label="Phone" required inputMode="tel" value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} />
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                        <Input label="Staff ID" value={form.staff_id} onChange={(e) => setForm({ ...form, staff_id: e.target.value })} placeholder="auto if empty" />
                        <Input label="License" value={form.license_number} onChange={(e) => setForm({ ...form, license_number: e.target.value })} placeholder="optional" />
                    </div>
                    {locations.length > 0 && (
                        <select
                            value={form.location_id}
                            onChange={(e) => setForm({ ...form, location_id: e.target.value })}
                            className="block w-full rounded-xl border-0 bg-dark-600 py-3 px-4 text-gray-200 ring-1 ring-inset ring-white/5 focus:ring-2 focus:ring-brand-500/50 text-sm transition-all"
                        >
                            <option value="">No location (floating)</option>
                            {locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}
                        </select>
                    )}
                    <label className="flex items-center gap-2 cursor-pointer">
                        <input type="checkbox" checked={form.create_login} onChange={(e) => setForm({ ...form, create_login: e.target.checked })} className="h-4 w-4 rounded border-white/10 bg-dark-600 text-brand-500" />
                        <span className="text-sm text-gray-300">Create login for driver panel</span>
                    </label>
                    {form.create_login && (
                        <div className="space-y-3 p-3 rounded-xl bg-dark-700/30 border border-white/5">
                            <Input icon={Mail} label="Email" type="email" required value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} placeholder="driver@example.com" autoComplete="off" />
                            <PasswordInline value={form.password} onChange={(v) => setForm({ ...form, password: v })} show={showPwd} onToggle={() => setShowPwd(s => !s)} />
                        </div>
                    )}
                    <div className="flex justify-end gap-3 pt-2">
                        <Button variant="ghost" type="button" onClick={() => setShowModal(false)}>Cancel</Button>
                        <Button type="submit" disabled={saving}>{saving ? 'Adding...' : 'Add Driver'}</Button>
                    </div>
                </form>
            </Modal>

            <Modal isOpen={editModal} onClose={() => setEditModal(false)} title="Edit Driver">
                <form onSubmit={handleEdit} className="space-y-4">
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <Input label="Name" required value={editForm.name} onChange={(e) => setEditForm({ ...editForm, name: e.target.value })} />
                        <Input icon={Phone} label="Phone" required inputMode="tel" value={editForm.phone} onChange={(e) => setEditForm({ ...editForm, phone: e.target.value })} />
                    </div>
                    {locations.length > 0 && (
                        <div className="space-y-1.5">
                            <label className="block text-sm font-medium text-gray-300">Assigned Location</label>
                            <select
                                value={editForm.location_id}
                                onChange={(e) => setEditForm({ ...editForm, location_id: e.target.value })}
                                className="block w-full rounded-xl border-0 bg-dark-600 py-3 px-4 text-gray-200 ring-1 ring-inset ring-white/5 focus:ring-2 focus:ring-brand-500/50 text-sm transition-all"
                            >
                                <option value="">Unassigned</option>
                                {locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}
                            </select>
                        </div>
                    )}
                    <div className="flex justify-end gap-3 pt-2">
                        <Button variant="ghost" type="button" onClick={() => setEditModal(false)}>Cancel</Button>
                        <Button type="submit" disabled={savingEdit}>{savingEdit ? 'Saving...' : 'Save Changes'}</Button>
                    </div>
                </form>
            </Modal>
        </div>
    );
};

const PasswordInline = ({ value, onChange, show, onToggle }) => (
    <div className="space-y-1.5">
        <label className="block text-sm font-medium text-gray-300">Password</label>
        <div className="relative group">
            <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3.5">
                <Key className="h-4 w-4 text-gray-500 group-focus-within:text-brand-500 transition-colors" />
            </div>
            <input
                type={show ? 'text' : 'password'}
                required
                autoComplete="new-password"
                value={value}
                onChange={(e) => onChange(e.target.value)}
                placeholder="Min 8 chars, letter + number"
                className="block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-10 text-gray-200 placeholder:text-gray-500 ring-1 ring-inset ring-white/5 focus:ring-2 focus:ring-brand-500/50 text-sm transition-all"
            />
            <button type="button" onClick={onToggle} className="absolute inset-y-0 right-0 flex items-center pr-3 text-gray-500 hover:text-gray-300">
                {show ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
            </button>
        </div>
    </div>
);

export default CompanyDetail;
