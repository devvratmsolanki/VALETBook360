import { useState, useEffect } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { getDriversByCompany, createDriver, updateDriver, toggleDriverActive, deleteDriver } from '../../services/driverService';
import { getLocationsByCompany } from '../../services/locationService';
import { createStaff } from '../../services/userService';
import { isValidEmail, isValidPhone, isValidPassword, normalizePhone } from '../../lib/utils';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Modal from '../../components/ui/Modal';
import Input from '../../components/ui/Input';
import Badge from '../../components/ui/Badge';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import { toast } from '../../components/ui/Toast';
import { Users, Plus, Phone, CreditCard, UserCheck, UserX, Mail, Key, MapPin, Eye, EyeOff, Trash2, Edit2 } from 'lucide-react';

const emptyForm = {
    name: '', phone: '', license_number: '', staff_id: '',
    create_login: true, email: '', password: '', location_id: '',
};

const Drivers = () => {
    const { companyId } = useAuth();
    const [drivers, setDrivers] = useState([]);
    const [locations, setLocations] = useState([]);
    const [loading, setLoading] = useState(true);
    const [showModal, setShowModal] = useState(false);
    const [formData, setFormData] = useState(emptyForm);
    const [errors, setErrors] = useState({});
    const [saving, setSaving] = useState(false);
    const [showPwd, setShowPwd] = useState(false);

    // Edit state
    const [editModal, setEditModal] = useState(false);
    const [editData, setEditData] = useState({ id: null, name: '', phone: '', license_number: '', staff_id: '', location_id: '' });
    const [editErrors, setEditErrors] = useState({});
    const [savingEdit, setSavingEdit] = useState(false);

    const fetchAll = async () => {
        if (!companyId) { setLoading(false); return; }
        try {
            const [d, l] = await Promise.all([
                getDriversByCompany(companyId),
                getLocationsByCompany(companyId),
            ]);
            setDrivers(d);
            setLocations(l);
        } catch (err) {
            toast.error(err?.message || 'Failed to load drivers');
        } finally {
            setLoading(false);
        }
    };
    useEffect(() => { fetchAll(); }, [companyId]);

    const validate = () => {
        const next = {};
        if (!formData.name.trim() || formData.name.trim().length < 2) next.name = 'Name must be at least 2 characters';
        if (!isValidPhone(formData.phone)) next.phone = 'Enter a valid phone (7–15 digits)';
        if (formData.create_login) {
            if (!isValidEmail(formData.email)) next.email = 'Enter a valid email';
            if (!isValidPassword(formData.password)) next.password = 'Min 8 chars with a letter and a number';
        }
        setErrors(next);
        return Object.keys(next).length === 0;
    };

    const closeModal = () => {
        setShowModal(false);
        setFormData(emptyForm);
        setErrors({});
        setShowPwd(false);
    };

    const handleCreate = async (e) => {
        e.preventDefault();
        if (!validate()) return;
        setSaving(true);
        try {
            let userId = null;
            if (formData.create_login) {
                const result = await createStaff({
                    email: formData.email.trim().toLowerCase(),
                    password: formData.password,
                    name: formData.name.trim(),
                    role: 'driver',
                    company_id: companyId,
                    location_id: formData.location_id || null,
                });
                userId = result?.user?.id || null;
            }
            await createDriver({
                valet_company_id: companyId,
                name: formData.name.trim(),
                phone: normalizePhone(formData.phone),
                license_number: formData.license_number.trim() || null,
                staff_id: formData.staff_id.trim() || null,
                location_id: formData.location_id || null,
                user_id: userId,
                email: formData.create_login ? formData.email.trim().toLowerCase() : null,
                active: true,
            });
            toast.success(formData.create_login ? 'Driver added with login' : 'Driver added');
            closeModal();
            fetchAll();
        } catch (err) {
            toast.error(err.message || 'Failed to create driver');
        } finally {
            setSaving(false);
        }
    };

    const startEdit = (d) => {
        setEditData({
            id: d.id,
            name: d.name || '',
            phone: d.phone || '',
            license_number: d.license_number || '',
            staff_id: d.staff_id || '',
            location_id: d.location_id || '',
        });
        setEditErrors({});
        setEditModal(true);
    };

    const handleEdit = async (e) => {
        e.preventDefault();
        const next = {};
        if (!editData.name.trim() || editData.name.trim().length < 2) next.name = 'Name must be at least 2 characters';
        if (!isValidPhone(editData.phone)) next.phone = 'Enter a valid phone (7–15 digits)';
        setEditErrors(next);
        if (Object.keys(next).length) return;
        setSavingEdit(true);
        try {
            await updateDriver(editData.id, {
                name: editData.name.trim(),
                phone: normalizePhone(editData.phone),
                license_number: editData.license_number.trim() || null,
                staff_id: editData.staff_id.trim() || null,
                location_id: editData.location_id || null,
            });
            toast.success('Driver updated');
            setEditModal(false);
            fetchAll();
        } catch (err) {
            toast.error(err.userMessage || err.message);
        } finally {
            setSavingEdit(false);
        }
    };

    const handleToggle = async (id, active) => {
        try {
            await toggleDriverActive(id, !active);
            toast.success(active ? 'Driver deactivated' : 'Driver activated');
            fetchAll();
        } catch (err) {
            toast.error(err?.message || 'Failed to update');
        }
    };

    const handleDelete = async (driver) => {
        const hasLogin = !!driver.user_id;
        const msg = hasLogin
            ? `Delete driver "${driver.name}"? This also removes their login. Historical transactions stay but lose the driver name.`
            : `Delete driver "${driver.name}"? Historical transactions stay but lose the driver name.`;
        if (!confirm(msg)) return;
        try {
            await deleteDriver(driver.id);
            toast.success('Driver deleted');
            fetchAll();
        } catch (err) {
            toast.error(err.message || 'Failed to delete driver');
        }
    };

    const activeCount = drivers.filter(d => d.active).length;

    return (
        <div className="animate-fade-in">
            <div className="flex items-center justify-between mb-6">
                <div>
                    <h1 className="text-2xl font-bold text-white">Drivers</h1>
                    <p className="text-sm text-gray-500 mt-1">{activeCount} active of {drivers.length} total</p>
                </div>
                <Button onClick={() => setShowModal(true)}><Plus className="h-4 w-4" /> Add Driver</Button>
            </div>

            {loading ? <div className="flex justify-center py-12"><LoadingSpinner size="md" /></div>
                : drivers.length === 0
                    ? <Card className="p-8 text-center"><Users className="h-8 w-8 text-gray-600 mx-auto mb-3" /><p className="text-gray-500">No drivers added yet</p></Card>
                    : (
                        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                            {drivers.map((d) => (
                                <Card key={d.id} className="p-4">
                                    <div className="flex items-start justify-between">
                                        <div className="flex items-center gap-3">
                                            <div className={`h-10 w-10 rounded-full flex items-center justify-center text-sm font-bold ${d.active ? 'bg-emerald-500/10 text-emerald-400' : 'bg-gray-500/10 text-gray-500'}`}>
                                                {d.name?.charAt(0)?.toUpperCase() || '?'}
                                            </div>
                                            <div>
                                                <div className="flex items-center gap-2">
                                                    <p className="font-medium text-white text-sm">{d.name}</p>
                                                    <Badge className="bg-brand-500/10 text-brand-500 border-brand-500/20 text-[10px] py-0">{d.staff_id || 'N/A'}</Badge>
                                                </div>
                                                <p className="text-xs text-gray-500 flex items-center gap-1 mt-0.5"><Phone className="h-3 w-3" /> {d.phone || 'N/A'}</p>
                                                {d.license_number && <p className="text-xs text-gray-500 flex items-center gap-1 mt-0.5"><CreditCard className="h-3 w-3" /> {d.license_number}</p>}
                                                {d.user_id && <p className="text-[10px] text-emerald-400/80 flex items-center gap-1 mt-0.5"><Key className="h-3 w-3" /> Login enabled</p>}
                                            </div>
                                        </div>
                                        <div className="flex items-center gap-2">
                                            <Badge className={d.active ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20' : 'bg-gray-500/10 text-gray-500 border-gray-500/20'}>
                                                {d.active ? 'Active' : 'Inactive'}
                                            </Badge>
                                            <button onClick={() => startEdit(d)} aria-label="Edit driver" className="p-1.5 rounded-lg hover:bg-white/5 text-gray-500 hover:text-white transition-colors" title="Edit driver">
                                                <Edit2 className="h-4 w-4" />
                                            </button>
                                            <button onClick={() => handleToggle(d.id, d.active)} className="p-1.5 rounded-lg hover:bg-white/5 text-gray-500 hover:text-white transition-colors" title={d.active ? 'Deactivate' : 'Activate'}>
                                                {d.active ? <UserX className="h-4 w-4" /> : <UserCheck className="h-4 w-4" />}
                                            </button>
                                            <button onClick={() => handleDelete(d)} className="p-1.5 rounded-lg hover:bg-red-500/10 text-gray-600 hover:text-red-400 transition-colors" title="Delete driver">
                                                <Trash2 className="h-4 w-4" />
                                            </button>
                                        </div>
                                    </div>
                                </Card>
                            ))}
                        </div>
                    )}

            <Modal isOpen={showModal} onClose={closeModal} title="Add New Driver">
                <form onSubmit={handleCreate} className="space-y-4">
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <Input
                            label="Name"
                            required
                            value={formData.name}
                            onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                            placeholder="Driver name"
                            error={errors.name}
                        />
                        <Input
                            icon={Phone}
                            label="Phone"
                            required
                            inputMode="tel"
                            value={formData.phone}
                            onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
                            placeholder="e.g. 9876543210"
                            error={errors.phone}
                        />
                    </div>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <Input
                            label="Staff ID"
                            value={formData.staff_id}
                            onChange={(e) => setFormData({ ...formData, staff_id: e.target.value })}
                            placeholder="e.g. D-101 (auto if empty)"
                        />
                        <Input
                            icon={CreditCard}
                            label="License Number"
                            value={formData.license_number}
                            onChange={(e) => setFormData({ ...formData, license_number: e.target.value })}
                            placeholder="License number"
                        />
                    </div>

                    {locations.length > 0 && (
                        <div className="space-y-1.5">
                            <label className="block text-sm font-medium text-gray-300">Assigned Location</label>
                            <div className="relative">
                                <MapPin className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500" />
                                <select
                                    value={formData.location_id}
                                    onChange={(e) => setFormData({ ...formData, location_id: e.target.value })}
                                    className="block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-4 text-gray-200 ring-1 ring-inset ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all"
                                >
                                    <option value="">No location (floating)</option>
                                    {locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}
                                </select>
                            </div>
                        </div>
                    )}

                    <label className="flex items-center gap-2 cursor-pointer select-none">
                        <input
                            type="checkbox"
                            checked={formData.create_login}
                            onChange={(e) => setFormData({ ...formData, create_login: e.target.checked })}
                            className="h-4 w-4 rounded border-white/10 bg-dark-600 text-brand-500 focus:ring-brand-500/50"
                        />
                        <span className="text-sm text-gray-300">Create login for driver panel</span>
                    </label>

                    {formData.create_login && (
                        <div className="space-y-4 p-4 rounded-xl bg-dark-700/30 border border-white/5">
                            <Input
                                icon={Mail}
                                label="Email"
                                type="email"
                                required
                                value={formData.email}
                                onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                                placeholder="driver@example.com"
                                error={errors.email}
                                autoComplete="off"
                            />
                            <div className="space-y-1.5">
                                <label className="block text-sm font-medium text-gray-300">Password</label>
                                <div className="relative group">
                                    <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3.5">
                                        <Key className="h-4 w-4 text-gray-500 group-focus-within:text-brand-500 transition-colors" />
                                    </div>
                                    <input
                                        type={showPwd ? 'text' : 'password'}
                                        required
                                        autoComplete="new-password"
                                        value={formData.password}
                                        onChange={(e) => setFormData({ ...formData, password: e.target.value })}
                                        placeholder="Min 8 chars, letter + number"
                                        className={`block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-10 text-gray-200 placeholder:text-gray-500 ring-1 ring-inset ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all ${errors.password ? 'ring-red-500/50' : ''}`}
                                    />
                                    <button type="button" onClick={() => setShowPwd(s => !s)} className="absolute inset-y-0 right-0 flex items-center pr-3 text-gray-500 hover:text-gray-300">
                                        {showPwd ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                                    </button>
                                </div>
                                {errors.password && <p className="text-xs text-red-400">{errors.password}</p>}
                            </div>
                        </div>
                    )}

                    <div className="flex justify-end gap-3 pt-2">
                        <Button variant="ghost" type="button" onClick={closeModal}>Cancel</Button>
                        <Button type="submit" disabled={saving}>{saving ? 'Adding...' : 'Add Driver'}</Button>
                    </div>
                </form>
            </Modal>

            <Modal isOpen={editModal} onClose={() => setEditModal(false)} title="Edit Driver">
                <form onSubmit={handleEdit} className="space-y-4">
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <Input
                            label="Name"
                            required
                            value={editData.name}
                            onChange={(e) => setEditData({ ...editData, name: e.target.value })}
                            placeholder="Driver name"
                            error={editErrors.name}
                        />
                        <Input
                            icon={Phone}
                            label="Phone"
                            required
                            inputMode="tel"
                            value={editData.phone}
                            onChange={(e) => setEditData({ ...editData, phone: e.target.value })}
                            placeholder="e.g. 9876543210"
                            error={editErrors.phone}
                        />
                    </div>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <Input
                            label="Staff ID"
                            value={editData.staff_id}
                            onChange={(e) => setEditData({ ...editData, staff_id: e.target.value })}
                            placeholder="e.g. D-101"
                        />
                        <Input
                            icon={CreditCard}
                            label="License Number"
                            value={editData.license_number}
                            onChange={(e) => setEditData({ ...editData, license_number: e.target.value })}
                            placeholder="License number"
                        />
                    </div>
                    <div className="space-y-1.5">
                        <label className="block text-sm font-medium text-gray-300">Assigned Location</label>
                        <div className="relative">
                            <MapPin className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500" />
                            <select
                                value={editData.location_id}
                                onChange={(e) => setEditData({ ...editData, location_id: e.target.value })}
                                className="block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-4 text-gray-200 ring-1 ring-inset ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all"
                            >
                                <option value="">Unassigned</option>
                                {locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}
                            </select>
                        </div>
                    </div>
                    <div className="flex justify-end gap-3 pt-2">
                        <Button variant="ghost" type="button" onClick={() => setEditModal(false)}>Cancel</Button>
                        <Button type="submit" disabled={savingEdit}>{savingEdit ? 'Saving...' : 'Save Changes'}</Button>
                    </div>
                </form>
            </Modal>
        </div>
    );
};

export default Drivers;
