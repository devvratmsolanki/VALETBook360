import { useState, useEffect, useMemo } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import Card from '../../components/ui/Card';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import { toast } from '../../components/ui/Toast';
import { formatTime, formatDate } from '../../lib/utils';
import { MapPin, ArrowLeft, UserCheck, Car, Clock, Building2, Phone, Mail, Edit, Key, Plus, Trash2, Check, X, RefreshCw } from 'lucide-react';
import { updateLocation } from '../../services/locationService';
import { getSlotsByLocation, createSlot, updateSlotName, deleteSlot, bulkGenerateSlots, clearAllSlots } from '../../services/slotService';
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
        const activeTxs = transactions.filter(t => ['parked', 'requested', 'ready'].includes(t.status));
        const active = activeTxs.length;
        const delivered = transactions.filter(t => t.status === 'delivered').length;

        // Count unique occupied slots (using string matching for key_code)
        const occupiedCodes = new Set(activeTxs.map(t => t.key_code).filter(Boolean));
        const occupiedSlots = occupiedCodes.size;

        // Effective capacity is either count of custom slots or the numerical field
        const capacity = slots.length > 0 ? slots.length : (location?.key_capacity || 0);

        return { total: transactions.length, active, delivered, occupiedSlots, capacity };
    }, [transactions, slots, location?.key_capacity]);

    const handleUpdate = async (e) => {
        e.preventDefault();
        setSaving(true);
        try {
            const newCapacity = parseInt(editData.key_capacity) || 0;
            const updated = await updateLocation(locationId, {
                ...editData,
                key_capacity: newCapacity
            });

            // Sync slots and refresh state
            await syncSlotsWithCapacity(locationId, newCapacity);
            const freshSlots = await getSlotsByLocation(locationId);

            setLocation(updated);
            setSlots(freshSlots);
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

    if (loading) return <div className="flex items-center justify-center h-64"><div className="animate-spin h-8 w-8 border-2 border-brand-500 border-t-transparent rounded-full" /></div>;
    if (!location) return <div className="text-center py-12 text-gray-500">Location not found</div>;

    const tabs = [
        { id: 'overview', label: 'Overview' },
        { id: 'slots', label: `Key Slots (${slots.length > 0 ? slots.length : location?.key_capacity || 0})` },
        { id: 'drivers', label: `Drivers (${drivers.length})` },
        { id: 'transactions', label: `Transactions (${transactions.length})` },
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
                    <Edit className="h-4 w-4" /> Edit
                </Button>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
                <Card className="p-4 text-center">
                    <p className="text-2xl font-bold text-brand-400">{stats.total}</p>
                    <p className="text-xs text-gray-500 mt-1">Total Trips</p>
                </Card>
                <Card className="p-4 text-center">
                    <p className="text-2xl font-bold text-amber-400">{stats.active}</p>
                    <p className="text-xs text-gray-500 mt-1">Active Now</p>
                </Card>
                <Card className="p-4 text-center">
                    <div className="flex flex-col items-center">
                        <p className="text-2xl font-bold text-blue-400">{stats.occupiedSlots} <span className="text-xs text-gray-600">/ {stats.capacity}</span></p>
                        <p className="text-xs text-gray-500 mt-1">Key Slots Occupied</p>
                    </div>
                </Card>
                <Card className="p-4 text-center">
                    <p className="text-2xl font-bold text-emerald-400">{stats.delivered}</p>
                    <p className="text-xs text-gray-500 mt-1">Completed</p>
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

            {/* Overview Tab */}
            {activeTab === 'overview' && (
                <Card className="p-6">
                    <h3 className="text-sm font-semibold text-white mb-4 flex items-center gap-2"><MapPin className="h-4 w-4 text-brand-500" /> Location Details</h3>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        {[
                            { label: 'Name', value: location.name, icon: Building2 },
                            { label: 'Address', value: location.address, icon: MapPin },
                            { label: 'City', value: location.city },
                            { label: 'State', value: location.state },
                            { label: 'Key Slots', value: location.key_capacity, icon: Key },
                            { label: 'Added', value: formatDate(location.created_at), icon: Clock },
                        ].map((f, i) => (
                            <div key={i} className="flex items-start gap-3 px-3 py-2.5 rounded-xl bg-dark-600/50">
                                {f.icon && <f.icon className="h-4 w-4 text-gray-500 mt-0.5 shrink-0" />}
                                <div>
                                    <p className="text-[10px] text-gray-600 uppercase tracking-wider">{f.label}</p>
                                    <p className="text-sm text-gray-300">{f.value !== null && f.value !== undefined ? f.value : '—'}</p>
                                </div>
                            </div>
                        ))}
                    </div>
                </Card>
            )}

            {/* Key Slots Tab */}
            {activeTab === 'slots' && (
                <div className="space-y-4 animate-fade-in">
                    <div className="flex justify-between items-center bg-dark-700/50 p-4 rounded-2xl border border-white/5">
                        <div>
                            <p className="text-sm font-medium text-white">Manage Key nomenclature</p>
                            <p className="text-xs text-gray-500">Define custom names for your key slots (e.g. A1, Box 5)</p>
                        </div>
                        <Button size="sm" onClick={() => setShowBulkModal(true)}>
                            <Plus className="h-4 w-4 mr-1.5" /> Bulk Generate
                        </Button>
                    </div>

                    {slots.length === 0 ? (
                        <Card className="p-12 text-center">
                            <Key className="h-10 w-10 text-gray-600 mx-auto mb-4" />
                            <p className="text-white font-medium">No custom slots defined</p>
                            <p className="text-sm text-gray-500 mt-1 mb-6">The system currently uses numerical slots 1-{location?.key_capacity || 0}</p>
                            <Button variant="outline" onClick={() => setShowBulkModal(true)}>Create Custom Slots Now</Button>
                        </Card>
                    ) : (
                        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-3">
                            {slots.map(s => (
                                <div key={s.id} className={`group relative p-3 rounded-xl border transition-all ${editingSlotId === s.id ? 'bg-brand-500/10 border-brand-500/50 ring-1 ring-brand-500/20' : 'bg-dark-600 border-white/5 hover:border-brand-500/30'}`}>
                                    {editingSlotId === s.id ? (
                                        <div className="flex flex-col gap-2">
                                            <input autoFocus type="text" value={editingSlotName} onChange={(e) => setEditingSlotName(e.target.value)}
                                                className="w-full bg-dark-700 border-0 text-xs font-bold text-brand-400 p-1 rounded focus:ring-1 focus:ring-brand-500/50" />
                                            <div className="flex justify-end gap-1">
                                                <button onClick={() => setEditingSlotId(null)} className="p-1 rounded hover:bg-white/10 text-gray-400"><X className="h-3 w-3" /></button>
                                                <button onClick={() => handleUpdateSlot(s.id)} className="p-1 rounded bg-brand-400 text-black"><Check className="h-3 w-3" /></button>
                                            </div>
                                        </div>
                                    ) : (
                                        <>
                                            <div className="flex items-center justify-between mb-1">
                                                <span className="text-[10px] text-gray-600 uppercase font-mono">Slot</span>
                                                <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                                                    <button onClick={() => { setEditingSlotId(s.id); setEditingSlotName(s.slot_name); }} className="p-1 rounded hover:bg-white/10 text-gray-500 hover:text-white"><Edit className="h-3 w-3" /></button>
                                                    <button onClick={() => handleDeleteSlot(s.id)} className="p-1 rounded hover:bg-red-500/10 text-gray-500 hover:text-red-400"><Trash2 className="h-3 w-3" /></button>
                                                </div>
                                            </div>
                                            <p className="text-lg font-bold text-white text-center pb-1">{s.slot_name}</p>
                                        </>
                                    )}
                                </div>
                            ))}
                        </div>
                    )}
                </div>
            )}

            {/* Drivers Tab */}
            {activeTab === 'drivers' && (
                <div>
                    {drivers.length === 0 ? (
                        <Card className="p-8 text-center"><UserCheck className="h-8 w-8 text-gray-600 mx-auto mb-3" /><p className="text-gray-500 text-sm">No drivers yet. Add drivers from the Drivers page.</p></Card>
                    ) : (
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                            {drivers.map(d => (
                                <Card key={d.id} className="p-4">
                                    <div className="flex items-center gap-3">
                                        <div className={`h-10 w-10 rounded-full flex items-center justify-center text-sm font-bold ${d.active ? 'bg-emerald-500/10 text-emerald-400' : 'bg-gray-500/10 text-gray-500'}`}>
                                            {d.name?.charAt(0)?.toUpperCase() || 'D'}
                                        </div>
                                        <div className="flex-1">
                                            <p className="text-sm font-medium text-white">{d.name}</p>
                                            <div className="flex items-center gap-3 mt-0.5">
                                                {d.phone && <span className="text-xs text-gray-500 flex items-center gap-1"><Phone className="h-3 w-3" />{d.phone}</span>}
                                                {d.email && <span className="text-xs text-gray-500 flex items-center gap-1"><Mail className="h-3 w-3" />{d.email}</span>}
                                            </div>
                                        </div>
                                        <Badge variant={d.active ? 'success' : 'default'}>{d.active ? 'Active' : 'Inactive'}</Badge>
                                    </div>
                                </Card>
                            ))}
                        </div>
                    )}
                </div>
            )}

            {/* Transactions Tab */}
            {activeTab === 'transactions' && (
                <div>
                    {transactions.length === 0 ? (
                        <Card className="p-8 text-center"><Car className="h-8 w-8 text-gray-600 mx-auto mb-3" /><p className="text-gray-500 text-sm">No transactions at this location yet.</p></Card>
                    ) : (
                        <Card className="overflow-hidden">
                            <div className="overflow-x-auto">
                                <table className="w-full text-left text-sm">
                                    <thead className="bg-dark-700/50 text-xs uppercase text-gray-500">
                                        <tr>
                                            <th className="px-4 py-3">Guest</th>
                                            <th className="px-4 py-3">Car</th>
                                            <th className="px-4 py-3">Parked By</th>
                                            <th className="px-4 py-3">Retrieved By</th>
                                            <th className="px-4 py-3">Status</th>
                                            <th className="px-4 py-3">Time</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-white/5">
                                        {transactions.map(tx => (
                                            <tr key={tx.id} className="hover:bg-white/[0.02] transition-colors">
                                                <td className="px-4 py-3">
                                                    <p className="text-sm text-white">{tx.visitors?.name || '—'}</p>
                                                    <p className="text-xs text-gray-500">{tx.visitors?.phone}</p>
                                                </td>
                                                <td className="px-4 py-3">
                                                    <p className="text-sm text-white font-mono">{tx.cars?.car_number || '—'}</p>
                                                    <p className="text-xs text-gray-500">{[tx.cars?.make, tx.cars?.model].filter(Boolean).join(' ')}</p>
                                                </td>
                                                <td className="px-4 py-3 text-sm text-blue-400">{tx.parked_driver?.name || '—'}</td>
                                                <td className="px-4 py-3 text-sm text-emerald-400">{tx.retrieved_driver?.name || '—'}</td>
                                                <td className="px-4 py-3"><Badge variant={tx.status}>{tx.status}</Badge></td>
                                                <td className="px-4 py-3 text-xs text-gray-500">{formatTime(tx.created_at)}</td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        </Card>
                    )}
                </div>
            )}

            {/* Edit Modal */}
            <Modal isOpen={showEditModal} onClose={() => setShowEditModal(false)} title="Edit Location">
                <form onSubmit={handleUpdate} className="space-y-4">
                    <Input label="Name" required value={editData.name} onChange={(e) => setEditData({ ...editData, name: e.target.value })} placeholder="Location name" />
                    <Input label="Address" value={editData.address} onChange={(e) => setEditData({ ...editData, address: e.target.value })} placeholder="Street address" />
                    <div className="grid grid-cols-2 gap-3">
                        <Input label="City" value={editData.city} onChange={(e) => setEditData({ ...editData, city: e.target.value })} placeholder="City" />
                        <Input label="State" value={editData.state} onChange={(e) => setEditData({ ...editData, state: e.target.value })} placeholder="State" />
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                        <Input label="Country" value={editData.country} onChange={(e) => setEditData({ ...editData, country: e.target.value })} placeholder="Country" />
                        <Input label="Key Slots" type="number" min="0" value={editData.key_capacity} onChange={(e) => setEditData({ ...editData, key_capacity: e.target.value })} placeholder="e.g. 50" />
                    </div>
                    <div className="flex justify-end gap-3 pt-2">
                        <Button variant="ghost" type="button" onClick={() => setShowEditModal(false)}>Cancel</Button>
                        <Button type="submit" disabled={saving}>{saving ? 'Saving...' : 'Save Changes'}</Button>
                    </div>
                </form>
            </Modal>
            {/* Bulk Generate Modal */}
            <Modal isOpen={showBulkModal} onClose={() => setShowBulkModal(false)} title="Bulk Generate Slots">
                <form onSubmit={handleBulkGenerate} className="space-y-4">
                    <p className="text-xs text-gray-400">Quickly create numbered slots with a prefix. Existing slots will not be deleted.</p>
                    <div className="grid grid-cols-2 gap-3">
                        <Input label="Prefix (Optional)" value={bulkData.prefix} onChange={(e) => setBulkData({ ...bulkData, prefix: e.target.value })} placeholder="e.g. Box, A, Room" />
                        <Input label="How many slots?" type="number" required value={bulkData.count} onChange={(e) => setBulkData({ ...bulkData, count: parseInt(e.target.value) || 0 })} placeholder="30" />
                    </div>
                    <Input label="Start Numbering From" type="number" value={bulkData.startFrom} onChange={(e) => setBulkData({ ...bulkData, startFrom: parseInt(e.target.value) || 1 })} placeholder="1" />

                    <div className="bg-blue-500/5 border border-blue-500/20 p-3 rounded-xl">
                        <p className="text-[10px] text-blue-400 font-medium uppercase mb-1">Preview</p>
                        <p className="text-sm text-gray-300">
                            Will create {bulkData.count} slots: <span className="text-white font-mono">{bulkData.prefix}{bulkData.startFrom}</span> ... <span className="text-white font-mono">{bulkData.prefix}{bulkData.startFrom + (bulkData.count - 1)}</span>
                        </p>
                    </div>

                    <div className="flex justify-end gap-3 pt-2">
                        <Button variant="ghost" type="button" onClick={() => setShowBulkModal(false)}>Cancel</Button>
                        <Button type="submit" disabled={saving}>{saving ? 'Generating...' : 'Generate Slots'}</Button>
                    </div>
                </form>
            </Modal>
            {/* Bulk Generate Modal */}
            <Modal isOpen={showBulkModal} onClose={() => setShowBulkModal(false)} title="Bulk Generate Slots">
                <form onSubmit={handleBulkGenerate} className="space-y-4">
                    <p className="text-xs text-gray-400">Quickly create numbered slots with a prefix. Existing slots will not be deleted.</p>
                    <div className="grid grid-cols-2 gap-3">
                        <Input label="Prefix (Optional)" value={bulkData.prefix} onChange={(e) => setBulkData({ ...bulkData, prefix: e.target.value })} placeholder="e.g. Box, A, Room" />
                        <Input label="How many slots?" type="number" required value={bulkData.count} onChange={(e) => setBulkData({ ...bulkData, count: parseInt(e.target.value) || 0 })} placeholder="30" />
                    </div>
                    <Input label="Start Numbering From" type="number" value={bulkData.startFrom} onChange={(e) => setBulkData({ ...bulkData, startFrom: parseInt(e.target.value) || 1 })} placeholder="1" />

                    <div className="bg-blue-500/5 border border-blue-500/20 p-3 rounded-xl">
                        <p className="text-[10px] text-blue-400 font-medium uppercase mb-1">Preview</p>
                        <p className="text-sm text-gray-300">
                            Will create {bulkData.count} slots: <span className="text-white font-mono">{bulkData.prefix}{bulkData.startFrom}</span> ... <span className="text-white font-mono">{bulkData.prefix}{bulkData.startFrom + (bulkData.count - 1)}</span>
                        </p>
                    </div>

                    <div className="flex justify-end gap-3 pt-2">
                        <Button variant="ghost" type="button" onClick={() => setShowBulkModal(false)}>Cancel</Button>
                        <Button type="submit" disabled={saving}>{saving ? 'Generating...' : 'Generate Slots'}</Button>
                    </div>
                </form>
            </Modal>
        </div>
    );
};

export default LocationDetail;
