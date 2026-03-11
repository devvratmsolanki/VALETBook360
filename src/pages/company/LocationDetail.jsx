import { useState, useEffect, useMemo } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import Card from '../../components/ui/Card';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import { toast } from '../../components/ui/Toast';
import { formatTime, formatDate } from '../../lib/utils';
import { MapPin, ArrowLeft, UserCheck, Car, Clock, Building2, Phone, Mail, Edit, Key, Plus, Trash2, Check, X, RefreshCw, Activity } from 'lucide-react';
import { updateLocation } from '../../services/locationService';
import { getSlotsByLocation, createSlot, updateSlotName, deleteSlot, bulkGenerateSlots } from '../../services/slotService';
import Input from '../../components/ui/Input';
import Modal from '../../components/ui/Modal';

const LocationDetail = () => {
    const { locationId } = useParams();
    const navigate = useNavigate();
    const { companyId } = useAuth();
    const [location, setLocation] = useState(null);
    const [drivers, setDrivers] = useState([]);
    const [transactions, setTransactions] = useState([]);
    const [slots, setSlots] = useState([]);
    const [loading, setLoading] = useState(true);
    const [activeTab, setActiveTab] = useState('overview');
    const [showEditModal, setShowEditModal] = useState(false);
    const [showBulkModal, setShowBulkModal] = useState(false);
    const [bulkData, setBulkData] = useState({ prefix: '', count: 10, startFrom: 1 });
    const [editData, setEditData] = useState({ name: '', address: '', city: '', state: '', country: '', key_capacity: 0 });
    const [saving, setSaving] = useState(false);
    const [editingSlotId, setEditingSlotId] = useState(null);
    const [editingSlotName, setEditingSlotName] = useState('');

    useEffect(() => {
        if (!locationId) return;
        const load = async () => {
            try {
                const [locRes, drvRes, txRes, slotRes] = await Promise.all([
                    supabase.from('locations').select('*').eq('id', locationId).single(),
                    supabase.from('drivers').select('*').eq('valet_company_id', companyId).order('name'),
                    supabase.from('valet_transactions').select(`
                        *, visitors(name, phone), cars(car_number, make, model),
                        parked_driver:parked_by_driver_id(name),
                        retrieved_driver:retrieved_by_driver_id(name)
                    `).eq('location_id', locationId).order('created_at', { ascending: false }).limit(50),
                    getSlotsByLocation(locationId),
                ]);
                if (locRes.error) throw locRes.error;
                setLocation(locRes.data);
                setEditData(locRes.data);
                setDrivers(drvRes.data || []);
                setTransactions(txRes.data || []);
                setSlots(slotRes || []);
            } catch (err) {
                toast.error('Failed to load location');
                console.error(err);
            } finally {
                setLoading(false);
            }
        };
        load();
    }, [locationId, companyId]);

    const stats = useMemo(() => {
        const activeTxs = transactions.filter(t => ['parked', 'requested', 'ready', 'driver_assigned', 'en_route', 'arrived'].includes(t.status));
        const active = activeTxs.length;
        const delivered = transactions.filter(t => t.status === 'delivered').length;
        const occupiedCodes = new Set(activeTxs.map(t => t.key_code).filter(Boolean));
        const occupiedSlots = occupiedCodes.size;
        const capacity = slots.length > 0 ? slots.length : (location?.key_capacity || 0);

        return { total: transactions.length, active, delivered, occupiedSlots, capacity };
    }, [transactions, slots, location?.key_capacity]);

    const handleUpdate = async (e) => {
        e.preventDefault();
        setSaving(true);
        try {
            const updated = await updateLocation(locationId, editData);
            setLocation(updated);
            toast.success('Location updated');
            setShowEditModal(false);
        } catch (err) {
            toast.error(err.message);
        } finally {
            setSaving(false);
        }
    };

    const handleBulkGenerate = async (e) => {
        e.preventDefault();
        setSaving(true);
        try {
            await bulkGenerateSlots(locationId, bulkData.prefix, bulkData.count, bulkData.startFrom);
            const updatedSlots = await getSlotsByLocation(locationId);
            setSlots(updatedSlots);
            toast.success('Slots generated');
            setShowBulkModal(false);
        } catch (err) {
            toast.error(err.message);
        } finally {
            setSaving(false);
        }
    };

    const handleUpdateSlot = async (id) => {
        try {
            await updateSlotName(id, editingSlotName);
            setSlots(slots.map(s => s.id === id ? { ...s, slot_name: editingSlotName } : s));
            setEditingSlotId(null);
            toast.success('Slot updated');
        } catch (err) {
            toast.error(err.message);
        }
    };

    const handleDeleteSlot = async (id) => {
        if (!confirm('Are you sure you want to delete this slot?')) return;
        try {
            await deleteSlot(id);
            setSlots(slots.filter(s => s.id !== id));
            toast.success('Slot deleted');
        } catch (err) {
            toast.error(err.message);
        }
    };

    if (loading) return <div className="flex items-center justify-center h-64"><LoadingSpinner size="lg" /></div>;
    if (!location) return <div className="text-center py-12 text-gray-500">Location not found</div>;

    const tabs = [
        { id: 'overview', label: 'Overview' },
        { id: 'slots', label: `Key Slots (${slots.length || location?.key_capacity || 0})` },
        { id: 'drivers', label: `Drivers (${drivers.length})` },
        { id: 'transactions', label: `Activity (${transactions.length})` },
    ];

    return (
        <div className="animate-fade-in">
            {/* Header */}
            <div className="flex items-center gap-4 mb-6">
                <button onClick={() => navigate('/company/locations')} className="p-2 rounded-xl hover:bg-white/5 text-gray-400 hover:text-white transition-colors">
                    <ArrowLeft className="h-5 w-5" />
                </button>
                <div className="flex-1">
                    <h1 className="text-2xl font-bold text-white">{location.name}</h1>
                    <p className="text-sm text-gray-500 mt-0.5">{[location.address, location.city, location.state].filter(Boolean).join(', ')}</p>
                </div>
                <Button variant="outline" size="sm" onClick={() => setShowEditModal(true)}>
                    <Edit className="h-4 w-4 mr-1.5" /> Edit Location
                </Button>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
                <Card className="p-4 bg-brand-500/5 border-brand-500/10">
                    <p className="text-2xl font-bold text-brand-400">{stats.total}</p>
                    <p className="text-[10px] uppercase text-gray-500 font-semibold mt-1 tracking-wider">Total Visits</p>
                </Card>
                <Card className="p-4 bg-amber-500/5 border-amber-500/10">
                    <p className="text-2xl font-bold text-amber-400">{stats.active}</p>
                    <p className="text-[10px] uppercase text-gray-500 font-semibold mt-1 tracking-wider">Active Now</p>
                </Card>
                <Card className="p-4 bg-blue-500/5 border-blue-500/10">
                    <p className="text-2xl font-bold text-blue-400">{stats.occupiedSlots} <span className="text-xs text-gray-600 font-normal">/ {stats.capacity}</span></p>
                    <p className="text-[10px] uppercase text-gray-500 font-semibold mt-1 tracking-wider">Keys In</p>
                </Card>
                <Card className="p-4 bg-emerald-500/5 border-emerald-500/10">
                    <p className="text-2xl font-bold text-emerald-400">{stats.delivered}</p>
                    <p className="text-[10px] uppercase text-gray-500 font-semibold mt-1 tracking-wider">Completed</p>
                </Card>
            </div>

            {/* Tabs */}
            <div className="flex gap-2 mb-6 border-b border-white/5 pb-3">
                {tabs.map(t => (
                    <button key={t.id} onClick={() => setActiveTab(t.id)}
                        className={`px-4 py-2 rounded-xl text-sm font-medium transition-all ${activeTab === t.id ? 'bg-brand-500/10 text-brand-400 border border-brand-500/20' : 'text-gray-500 hover:text-white hover:bg-white/5 border border-transparent'}`}>
                        {t.label}
                    </button>
                ))}
            </div>

            {/* Tab Content */}
            <div className="min-h-[400px]">
                {activeTab === 'overview' && (
                    <Card className="p-6">
                        <h3 className="text-sm font-semibold text-white mb-4 flex items-center gap-2"><Activity className="h-4 w-4 text-brand-500" /> Location Profile</h3>
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                            {[
                                { label: 'Name', value: location.name, icon: Building2 },
                                { label: 'Address', value: location.address, icon: MapPin },
                                { label: 'City', value: location.city },
                                { label: 'State', value: location.state },
                                { label: 'Key Capacity', value: location.key_capacity, icon: Key },
                                { label: 'Registration Date', value: formatDate(location.created_at), icon: Clock },
                            ].map((f, i) => (
                                <div key={i} className="flex items-start gap-3 px-4 py-3 rounded-2xl bg-dark-600/50 border border-white/5">
                                    {f.icon && <f.icon className="h-4 w-4 text-gray-500 mt-0.5 shrink-0" />}
                                    <div>
                                        <p className="text-[10px] text-gray-600 uppercase tracking-widest font-bold">{f.label}</p>
                                        <p className="text-sm text-gray-200 mt-0.5">{f.value || '—'}</p>
                                    </div>
                                </div>
                            ))}
                        </div>
                    </Card>
                )}

                {activeTab === 'slots' && (
                    <div className="space-y-4 animate-fade-in">
                        <div className="flex justify-between items-center bg-dark-700/50 p-4 rounded-2xl border border-white/5">
                            <div>
                                <p className="text-sm font-medium text-white">Advanced Key Management</p>
                                <p className="text-xs text-gray-500">Define custom labels for your key storage (e.g. VIP-1, Box A)</p>
                            </div>
                            <Button size="sm" onClick={() => setShowBulkModal(true)}>
                                <Plus className="h-4 w-4 mr-1.5" /> Bulk Setup
                            </Button>
                        </div>

                        {slots.length === 0 ? (
                            <Card className="p-16 text-center border-dashed border-white/10">
                                <Key className="h-12 w-12 text-gray-700 mx-auto mb-4" />
                                <p className="text-white font-bold">Standard Numbering Active</p>
                                <p className="text-sm text-gray-500 mt-1 mb-8">Currently using generic slots 1 through {location?.key_capacity || 0}</p>
                                <Button variant="outline" onClick={() => setShowBulkModal(true)} className="rounded-xl px-8 border-brand-500/30 text-brand-400 hover:bg-brand-500/10">Setup Custom Labels</Button>
                            </Card>
                        ) : (
                            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-3">
                                {slots.map(s => (
                                    <div key={s.id} className={`group relative p-4 rounded-2xl border transition-all ${editingSlotId === s.id ? 'bg-brand-500/10 border-brand-500/50 ring-2 ring-brand-500/10' : 'bg-dark-600 border-white/5 hover:border-brand-500/30 hover:-translate-y-1'}`}>
                                        {editingSlotId === s.id ? (
                                            <div className="flex flex-col gap-3">
                                                <input autoFocus type="text" value={editingSlotName} onChange={(e) => setEditingSlotName(e.target.value)}
                                                    className="w-full bg-dark-700 border-0 text-sm font-bold text-white p-2 rounded-lg focus:ring-2 focus:ring-brand-500/50" />
                                                <div className="flex justify-end gap-2">
                                                    <button onClick={() => setEditingSlotId(null)} className="p-1.5 rounded-lg hover:bg-white/10 text-gray-400">Cancel</button>
                                                    <button onClick={() => handleUpdateSlot(s.id)} className="p-1.5 rounded-lg bg-brand-500 text-black font-bold text-xs px-3">Save</button>
                                                </div>
                                            </div>
                                        ) : (
                                            <>
                                                <div className="flex items-center justify-between mb-2">
                                                    <span className="text-[9px] text-gray-600 uppercase font-black tracking-tighter">Key Label</span>
                                                    <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                                                        <button onClick={() => { setEditingSlotId(s.id); setEditingSlotName(s.slot_name); }} className="p-1.5 rounded-lg hover:bg-white/10 text-gray-500 hover:text-white transition-colors"><Edit className="h-3.5 w-3.5" /></button>
                                                        <button onClick={() => handleDeleteSlot(s.id)} className="p-1.5 rounded-lg hover:bg-red-500/10 text-gray-500 hover:text-red-400 transition-colors"><Trash2 className="h-3.5 w-3.5" /></button>
                                                    </div>
                                                </div>
                                                <p className="text-xl font-black text-white text-center py-2 tracking-widest">{s.slot_name}</p>
                                            </>
                                        )}
                                    </div>
                                ))}
                            </div>
                        )}
                    </div>
                )}

                {activeTab === 'drivers' && (
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-3 animate-fade-in">
                        {drivers.length === 0 ? (
                            <Card className="p-12 text-center col-span-2"><UserCheck className="h-10 w-10 text-gray-700 mx-auto mb-3" /><p className="text-gray-500">No drivers assigned to this company yet.</p></Card>
                        ) : drivers.map(d => (
                            <Card key={d.id} className="p-4 hover:border-white/10 transition-colors">
                                <div className="flex items-center gap-4">
                                    <div className={`h-12 w-12 rounded-2xl flex items-center justify-center text-lg font-black ${d.active ? 'bg-emerald-500/10 text-emerald-400' : 'bg-gray-500/10 text-gray-500'}`}>
                                        {d.name?.charAt(0)?.toUpperCase()}
                                    </div>
                                    <div className="flex-1">
                                        <p className="font-bold text-white mb-0.5">{d.name}</p>
                                        <div className="flex items-center gap-3">
                                            {d.phone && <span className="text-xs text-gray-500 flex items-center gap-1"><Phone className="h-3 w-3" /> {d.phone}</span>}
                                            <Badge variant={d.active ? 'success' : 'default'} className="text-[10px] py-0">{d.active ? 'ACTIVE' : 'INACTIVE'}</Badge>
                                        </div>
                                    </div>
                                </div>
                            </Card>
                        ))}
                    </div>
                )}

                {activeTab === 'transactions' && (
                    <Card className="overflow-hidden animate-fade-in">
                        <div className="overflow-x-auto">
                            <table className="w-full text-left text-sm">
                                <thead className="bg-dark-700/50 text-[10px] uppercase text-gray-500 font-bold tracking-widest">
                                    <tr>
                                        <th className="px-6 py-4">Guest \ Vehicle</th>
                                        <th className="px-6 py-4">Status</th>
                                        <th className="px-6 py-4">Drivers</th>
                                        <th className="px-6 py-4 text-right">Activity</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-white/5">
                                    {transactions.length === 0 ? (
                                        <tr><td colSpan="4" className="px-6 py-12 text-center text-gray-500">No visits recorded at this location</td></tr>
                                    ) : transactions.map(tx => (
                                        <tr key={tx.id} className="hover:bg-white/[0.02] transition-colors group">
                                            <td className="px-6 py-4">
                                                <div className="flex items-center gap-3">
                                                    <div className="bg-dark-600 p-2 rounded-xl border border-white/5 text-brand-400 group-hover:scale-110 transition-transform"><Car className="h-4 w-4" /></div>
                                                    <div>
                                                        <p className="font-bold text-white text-xs tracking-wider uppercase">{tx.cars?.car_number}</p>
                                                        <p className="text-[10px] text-gray-500 font-medium">{tx.visitors?.name || 'Guest'}</p>
                                                    </div>
                                                </div>
                                            </td>
                                            <td className="px-6 py-4"><Badge variant={tx.status} className="text-[10px] font-black">{tx.status}</Badge></td>
                                            <td className="px-6 py-4">
                                                <div className="flex flex-col gap-0.5">
                                                    <p className="text-[10px] text-blue-400 font-bold leading-none flex items-center gap-1">🅿️ {tx.parked_driver?.name || '—'}</p>
                                                    {tx.retrieved_driver && <p className="text-[10px] text-emerald-400 font-bold leading-none flex items-center gap-1 mt-1">🔄 {tx.retrieved_driver.name}</p>}
                                                </div>
                                            </td>
                                            <td className="px-6 py-4 text-right">
                                                <p className="text-xs text-gray-300 font-mono">{formatTime(tx.created_at)}</p>
                                                <p className="text-[10px] text-gray-600">{formatDate(tx.created_at)}</p>
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    </Card>
                )}
            </div>

            {/* Modals */}
            <Modal isOpen={showEditModal} onClose={() => setShowEditModal(false)} title="Edit Location Settings">
                <form onSubmit={handleUpdate} className="space-y-4">
                    <Input label="Display Name" required value={editData.name} onChange={(e) => setEditData({ ...editData, name: e.target.value })} placeholder="Location name" />
                    <Input label="Full Address" value={editData.address} onChange={(e) => setEditData({ ...editData, address: e.target.value })} placeholder="Street address" />
                    <div className="grid grid-cols-2 gap-4">
                        <Input label="City" value={editData.city} onChange={(e) => setEditData({ ...editData, city: e.target.value })} placeholder="City" />
                        <Input label="State" value={editData.state} onChange={(e) => setEditData({ ...editData, state: e.target.value })} placeholder="State" />
                    </div>
                    <div className="grid grid-cols-2 gap-4">
                        <Input label="Country" value={editData.country} onChange={(e) => setEditData({ ...editData, country: e.target.value })} placeholder="Country" />
                        <Input label="Key Slot Capacity" type="number" min="0" value={editData.key_capacity} onChange={(e) => setEditData({ ...editData, key_capacity: e.target.value })} placeholder="e.g. 50" />
                    </div>
                    <div className="flex justify-end gap-3 pt-4">
                        <Button variant="ghost" type="button" onClick={() => setShowEditModal(false)}>Cancel</Button>
                        <Button type="submit" disabled={saving}>{saving ? 'Saving...' : 'Save Configuration'}</Button>
                    </div>
                </form>
            </Modal>

            <Modal isOpen={showBulkModal} onClose={() => setShowBulkModal(false)} title="Bulk Key Slot Setup">
                <form onSubmit={handleBulkGenerate} className="space-y-5">
                    <div className="p-3 bg-brand-500/5 border border-brand-500/10 rounded-2xl">
                        <p className="text-xs text-gray-400 leading-relaxed">System will generate unique labels for your key storage. This will NOT affect active transactions.</p>
                    </div>
                    <div className="grid grid-cols-2 gap-4">
                        <Input label="Label Prefix" value={bulkData.prefix} onChange={(e) => setBulkData({ ...bulkData, prefix: e.target.value })} placeholder="e.g. A, BOX, V" />
                        <Input label="Quantity" type="number" required value={bulkData.count} onChange={(e) => setBulkData({ ...bulkData, count: parseInt(e.target.value) || 0 })} placeholder="30" />
                    </div>
                    <Input label="Start Sequence From" type="number" value={bulkData.startFrom} onChange={(e) => setBulkData({ ...bulkData, startFrom: parseInt(e.target.value) || 1 })} placeholder="1" />

                    <div className="bg-dark-600/50 p-4 rounded-2xl border border-white/5">
                        <p className="text-[10px] text-gray-500 uppercase font-black mb-2 tracking-widest">Example Output</p>
                        <div className="flex items-center gap-2">
                            <Badge className="bg-brand-500/20 text-brand-400 font-mono tracking-tighter">{bulkData.prefix}{bulkData.startFrom}</Badge>
                            <div className="h-px flex-1 bg-white/5 mx-2" />
                            <Badge className="bg-brand-500/20 text-brand-400 font-mono tracking-tighter">{bulkData.prefix}{bulkData.startFrom + (bulkData.count - 1)}</Badge>
                        </div>
                    </div>

                    <div className="flex justify-end gap-3 pt-2">
                        <Button variant="ghost" type="button" onClick={() => setShowBulkModal(false)}>Cancel</Button>
                        <Button type="submit" disabled={saving} className="bg-brand-500 text-black shadow-lg shadow-brand-500/20">
                            {saving ? 'Generating...' : 'Setup Slots Now'}
                        </Button>
                    </div>
                </form>
            </Modal>
        </div>
    );
};

export default LocationDetail;
