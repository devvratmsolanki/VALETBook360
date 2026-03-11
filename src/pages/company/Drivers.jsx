import { useState, useEffect } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { getDriversByCompany, createDriver, toggleDriverActive } from '../../services/driverService';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Modal from '../../components/ui/Modal';
import Input from '../../components/ui/Input';
import Badge from '../../components/ui/Badge';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import { toast } from '../../components/ui/Toast';
import { Users, Plus, Phone, CreditCard, UserCheck, UserX } from 'lucide-react';

const Drivers = () => {
    const { companyId } = useAuth();
    const [drivers, setDrivers] = useState([]);
    const [loading, setLoading] = useState(true);
    const [showModal, setShowModal] = useState(false);
    const [formData, setFormData] = useState({ name: '', phone: '', license_number: '', staff_id: '' });
    const [saving, setSaving] = useState(false);

    const fetchDrivers = async () => { try { setDrivers(companyId ? await getDriversByCompany(companyId) : []); } catch { toast.error('Failed to load drivers'); } finally { setLoading(false); } };
    useEffect(() => { fetchDrivers(); }, [companyId]);

    const handleCreate = async (e) => {
        e.preventDefault();
        if (!formData.name || formData.name.trim().length < 2) return toast.error('Driver name must be at least 2 characters');
        const phoneDigits = (formData.phone || '').replace(/\D/g, '');
        if (phoneDigits.length < 10) return toast.error('Phone must have at least 10 digits');
        setSaving(true); try { await createDriver({ ...formData, valet_company_id: companyId, active: true }); toast.success('Driver added'); setShowModal(false); setFormData({ name: '', phone: '', license_number: '', staff_id: '' }); fetchDrivers(); } catch (err) { toast.error(err.message); } finally { setSaving(false); }
    };
    const handleToggle = async (id, active) => { try { await toggleDriverActive(id, !active); toast.success(active ? 'Driver deactivated' : 'Driver activated'); fetchDrivers(); } catch { toast.error('Failed to update'); } };
    const activeCount = drivers.filter(d => d.active).length;

    return (
        <div className="animate-fade-in">
            <div className="flex items-center justify-between mb-6"><div><h1 className="text-2xl font-bold text-white">Drivers</h1><p className="text-sm text-gray-500 mt-1">{activeCount} active of {drivers.length} total</p></div><Button onClick={() => setShowModal(true)}><Plus className="h-4 w-4" /> Add Driver</Button></div>
            {loading ? <div className="flex justify-center py-12"><LoadingSpinner size="md" /></div> : drivers.length === 0 ? <Card className="p-8 text-center"><Users className="h-8 w-8 text-gray-600 mx-auto mb-3" /><p className="text-gray-500">No drivers added yet</p></Card> : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">{drivers.map((d) => (<Card key={d.id} className="p-4"><div className="flex items-start justify-between"><div className="flex items-center gap-3"><div className={`h-10 w-10 rounded-full flex items-center justify-center text-sm font-bold ${d.active ? 'bg-emerald-500/10 text-emerald-400' : 'bg-gray-500/10 text-gray-500'}`}>{d.name?.charAt(0)?.toUpperCase() || '?'}</div><div><div className="flex items-center gap-2"><p className="font-medium text-white text-sm">{d.name}</p><Badge className="bg-brand-500/10 text-brand-500 border-brand-500/20 text-[10px] py-0">{d.staff_id || 'N/A'}</Badge></div><p className="text-xs text-gray-500 flex items-center gap-1 mt-0.5"><Phone className="h-3 w-3" /> {d.phone || 'N/A'}</p>{d.license_number && <p className="text-xs text-gray-500 flex items-center gap-1 mt-0.5"><CreditCard className="h-3 w-3" /> {d.license_number}</p>}</div></div><div className="flex items-center gap-2"><Badge className={d.active ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20' : 'bg-gray-500/10 text-gray-500 border-gray-500/20'}>{d.active ? 'Active' : 'Inactive'}</Badge><button onClick={() => handleToggle(d.id, d.active)} className="p-1.5 rounded-lg hover:bg-white/5 text-gray-500 hover:text-white transition-colors" title={d.active ? 'Deactivate' : 'Activate'}>{d.active ? <UserX className="h-4 w-4" /> : <UserCheck className="h-4 w-4" />}</button></div></div></Card>))}</div>
            )}
            <Modal isOpen={showModal} onClose={() => setShowModal(false)} title="Add New Driver"><form onSubmit={handleCreate} className="space-y-4"><Input label="Name" required value={formData.name} onChange={(e) => setFormData({ ...formData, name: e.target.value })} placeholder="Driver name" /><div className="grid grid-cols-2 gap-4"><Input icon={Phone} label="Phone" required value={formData.phone} onChange={(e) => setFormData({ ...formData, phone: e.target.value })} placeholder="Phone number" /><Input label="Staff ID" value={formData.staff_id} onChange={(e) => setFormData({ ...formData, staff_id: e.target.value })} placeholder="e.g. D-101 (Auto if empty)" /></div><Input icon={CreditCard} label="License Number" value={formData.license_number} onChange={(e) => setFormData({ ...formData, license_number: e.target.value })} placeholder="License number" /><div className="flex justify-end gap-3 pt-2"><Button variant="ghost" type="button" onClick={() => setShowModal(false)}>Cancel</Button><Button type="submit" disabled={saving}>{saving ? 'Adding...' : 'Add Driver'}</Button></div></form></Modal>
        </div>
    );
};

export default Drivers;
