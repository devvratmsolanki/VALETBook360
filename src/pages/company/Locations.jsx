import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import { getLocationsByCompany, createLocation, deleteLocation } from '../../services/locationService';
import { syncSlotsWithCapacity } from '../../services/slotService';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Modal from '../../components/ui/Modal';
import Input from '../../components/ui/Input';
import { toast } from '../../components/ui/Toast';
import { MapPin, Plus, Trash2, ChevronRight } from 'lucide-react';

const Locations = () => {
    const { companyId } = useAuth();
    const navigate = useNavigate();
    const [locations, setLocations] = useState([]);
    const [loading, setLoading] = useState(true);
    const [showModal, setShowModal] = useState(false);
    const [formData, setFormData] = useState({ name: '', address: '', city: '', state: '', country: '', key_capacity: 0 });
    const [saving, setSaving] = useState(false);

    const fetchLocations = async () => { try { setLocations(companyId ? await getLocationsByCompany(companyId) : []); } catch { toast.error('Failed to load locations'); } finally { setLoading(false); } };
    useEffect(() => { fetchLocations(); }, [companyId]);
    const handleCreate = async (e) => {
        e.preventDefault();
        if (!formData.name || formData.name.trim().length < 2) return toast.error('Location name must be at least 2 characters');
        setSaving(true);
        try {
            const capacity = parseInt(formData.key_capacity) || 0;
            const loc = await createLocation({ ...formData, key_capacity: capacity, valet_company_id: companyId });

            // Sync slots immediately if capacity entered
            if (capacity > 0) {
                await syncSlotsWithCapacity(loc.id, capacity);
            }

            toast.success('Location added');
            setShowModal(false);
            setFormData({ name: '', address: '', city: '', state: '', country: '', key_capacity: 0 });
            fetchLocations();
        } catch (err) {
            toast.error(err.message);
        } finally {
            setSaving(false);
        }
    };
    const handleDelete = async (id, e) => { e.stopPropagation(); if (!confirm('Delete this location?')) return; try { await deleteLocation(id); toast.success('Location deleted'); fetchLocations(); } catch { toast.error('Failed to delete'); } };

    return (
        <div className="animate-fade-in">
            <div className="flex items-center justify-between mb-6"><div><h1 className="text-2xl font-bold text-white">Locations</h1><p className="text-sm text-gray-500 mt-1">{locations.length} locations</p></div><Button onClick={() => setShowModal(true)}><Plus className="h-4 w-4" /> Add Location</Button></div>
            {loading ? <div className="flex justify-center py-12"><div className="animate-spin h-6 w-6 border-2 border-brand-500 border-t-transparent rounded-full" /></div> : locations.length === 0 ? <Card className="p-8 text-center"><MapPin className="h-8 w-8 text-gray-600 mx-auto mb-3" /><p className="text-gray-500">No locations yet</p></Card> : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">{locations.map((loc) => (<Card key={loc.id} className="p-5 cursor-pointer hover:border-brand-500/20 hover:bg-white/[0.02] transition-all group" onClick={() => navigate(`/company/locations/${loc.id}`)}><div className="flex items-start justify-between"><div className="flex items-start gap-3"><div className="bg-brand-500/10 p-2 rounded-xl"><MapPin className="h-5 w-5 text-brand-400" /></div><div><p className="font-medium text-white text-sm">{loc.name}</p>{loc.address && <p className="text-xs text-gray-500 mt-1">{loc.address}</p>}<p className="text-xs text-gray-600 mt-0.5">{[loc.city, loc.state, loc.country].filter(Boolean).join(', ')}</p><div className="flex items-center gap-2 mt-2"><span className="text-[10px] bg-brand-500/10 px-1.5 py-0.5 rounded text-brand-400 border border-brand-500/10">🔑 Key Slots: {loc.key_capacity || 0}</span></div></div></div><div className="flex items-center gap-1"><button onClick={(e) => handleDelete(loc.id, e)} className="p-1.5 rounded-lg hover:bg-red-500/10 text-gray-600 hover:text-red-400 transition-colors"><Trash2 className="h-4 w-4" /></button><ChevronRight className="h-4 w-4 text-gray-600 group-hover:text-brand-400 transition-colors" /></div></div></Card>))}</div>
            )}
            <Modal isOpen={showModal} onClose={() => setShowModal(false)} title="Add Location"><form onSubmit={handleCreate} className="space-y-4"><Input label="Name" required value={formData.name} onChange={(e) => setFormData({ ...formData, name: e.target.value })} placeholder="Location name" /><Input label="Address" value={formData.address} onChange={(e) => setFormData({ ...formData, address: e.target.value })} placeholder="Street address" /><div className="grid grid-cols-2 gap-3"><Input label="City" value={formData.city} onChange={(e) => setFormData({ ...formData, city: e.target.value })} placeholder="City" /><Input label="State" value={formData.state} onChange={(e) => setFormData({ ...formData, state: e.target.value })} placeholder="State" /></div><div className="grid grid-cols-2 gap-3"><Input label="Country" value={formData.country} onChange={(e) => setFormData({ ...formData, country: e.target.value })} placeholder="Country" /><Input label="Key Slots" type="number" min="0" value={formData.key_capacity} onChange={(e) => setFormData({ ...formData, key_capacity: e.target.value })} placeholder="e.g. 50" /></div><div className="flex justify-end gap-3 pt-2"><Button variant="ghost" type="button" onClick={() => setShowModal(false)}>Cancel</Button><Button type="submit" disabled={saving}>{saving ? 'Adding...' : 'Add Location'}</Button></div></form></Modal>
        </div>
    );
};

export default Locations;
