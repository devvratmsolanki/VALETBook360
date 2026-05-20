import { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { getLocations, createLocation, deleteLocation } from '../../services/locationService';
import { getCompanies } from '../../services/companyService';
import { syncSlotsWithCapacity } from '../../services/slotService';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Modal from '../../components/ui/Modal';
import Input from '../../components/ui/Input';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import { toast } from '../../components/ui/Toast';
import { MapPin, Plus, Trash2, ChevronRight, Building2, Search } from 'lucide-react';

const emptyForm = { name: '', address: '', city: '', state: '', country: '', key_capacity: 0, valet_company_id: '' };

const AdminLocations = () => {
    const navigate = useNavigate();
    const [locations, setLocations] = useState([]);
    const [companies, setCompanies] = useState([]);
    const [loading, setLoading] = useState(true);
    const [showModal, setShowModal] = useState(false);
    const [formData, setFormData] = useState(emptyForm);
    const [saving, setSaving] = useState(false);
    const [search, setSearch] = useState('');
    const [companyFilter, setCompanyFilter] = useState('');

    const fetchAll = async () => {
        try {
            const [l, c] = await Promise.all([getLocations(), getCompanies()]);
            setLocations(l);
            setCompanies(c);
        } catch {
            toast.error('Failed to load locations');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => { fetchAll(); }, []);

    const filtered = useMemo(() => {
        return locations.filter(loc => {
            if (companyFilter && loc.valet_company_id !== companyFilter) return false;
            if (!search) return true;
            const s = search.toLowerCase();
            return loc.name?.toLowerCase().includes(s)
                || loc.city?.toLowerCase().includes(s)
                || loc.valet_companies?.company_name?.toLowerCase().includes(s);
        });
    }, [locations, search, companyFilter]);

    const groupedByCompany = useMemo(() => {
        const map = new Map();
        for (const loc of filtered) {
            const key = loc.valet_company_id || 'orphan';
            if (!map.has(key)) {
                map.set(key, {
                    companyId: key,
                    companyName: loc.valet_companies?.company_name || 'Unaffiliated',
                    locations: [],
                });
            }
            map.get(key).locations.push(loc);
        }
        return Array.from(map.values());
    }, [filtered]);

    const handleCreate = async (e) => {
        e.preventDefault();
        if (!formData.name.trim() || formData.name.trim().length < 2) return toast.error('Location name must be at least 2 characters');
        if (!formData.valet_company_id) return toast.error('Pick a company for this location');
        setSaving(true);
        try {
            const capacity = parseInt(formData.key_capacity) || 0;
            const loc = await createLocation({ ...formData, key_capacity: capacity });
            if (capacity > 0) await syncSlotsWithCapacity(loc.id, capacity);
            toast.success('Location added');
            setShowModal(false);
            setFormData(emptyForm);
            fetchAll();
        } catch (err) {
            toast.error(err.message || 'Failed to create location');
        } finally {
            setSaving(false);
        }
    };

    const handleDelete = async (loc, e) => {
        e.stopPropagation();
        if (!confirm(`Delete location "${loc.name}"? Linked slots/drivers stay but lose this reference.`)) return;
        try {
            await deleteLocation(loc.id);
            toast.success('Location deleted');
            fetchAll();
        } catch {
            toast.error('Failed to delete');
        }
    };

    if (loading) return <div className="flex items-center justify-center h-64"><LoadingSpinner size="lg" /></div>;

    return (
        <div className="animate-fade-in">
            <div className="flex flex-wrap items-end justify-between gap-3 mb-6">
                <div>
                    <h1 className="text-2xl font-bold text-white">Locations</h1>
                    <p className="text-sm text-gray-500 mt-1">{locations.length} across {companies.length} {companies.length === 1 ? 'company' : 'companies'}</p>
                </div>
                <Button onClick={() => setShowModal(true)}><Plus className="h-4 w-4" /> Add Location</Button>
            </div>

            <div className="flex flex-wrap gap-3 mb-6">
                <div className="relative">
                    <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500" />
                    <input
                        type="text"
                        value={search}
                        onChange={(e) => setSearch(e.target.value)}
                        placeholder="Search locations..."
                        className="block w-64 rounded-xl border-0 bg-dark-600 py-2.5 pl-10 pr-4 text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 text-sm transition-all"
                    />
                </div>
                <select
                    value={companyFilter}
                    onChange={(e) => setCompanyFilter(e.target.value)}
                    className="rounded-xl border-0 bg-dark-600 py-2.5 px-4 text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 text-sm transition-all"
                >
                    <option value="">All companies</option>
                    {companies.map(c => <option key={c.id} value={c.id}>{c.company_name}</option>)}
                </select>
            </div>

            {groupedByCompany.length === 0 ? (
                <Card className="p-8 text-center">
                    <MapPin className="h-8 w-8 text-gray-600 mx-auto mb-3" />
                    <p className="text-gray-500">No locations match</p>
                </Card>
            ) : (
                <div className="space-y-6">
                    {groupedByCompany.map(group => (
                        <Card key={group.companyId} className="overflow-hidden">
                            <button
                                onClick={() => group.companyId !== 'orphan' && navigate(`/admin/companies/${group.companyId}`)}
                                className="w-full px-5 py-3 flex items-center justify-between border-b border-white/5 hover:bg-white/[0.02] transition-colors text-left"
                            >
                                <div className="flex items-center gap-3">
                                    <div className="bg-brand-500/10 p-2 rounded-xl">
                                        <Building2 className="h-4 w-4 text-brand-400" />
                                    </div>
                                    <div>
                                        <p className="font-semibold text-white">{group.companyName}</p>
                                        <p className="text-xs text-gray-500">{group.locations.length} location{group.locations.length === 1 ? '' : 's'}</p>
                                    </div>
                                </div>
                                {group.companyId !== 'orphan' && <ChevronRight className="h-4 w-4 text-gray-500" />}
                            </button>

                            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3 p-4">
                                {group.locations.map(loc => (
                                    <div
                                        key={loc.id}
                                        onClick={() => navigate(`/admin/companies/${loc.valet_company_id}`)}
                                        className="p-4 rounded-xl bg-dark-700/40 border border-white/5 hover:border-brand-500/20 cursor-pointer transition-all group"
                                    >
                                        <div className="flex items-start justify-between">
                                            <div className="flex items-start gap-3 min-w-0">
                                                <MapPin className="h-4 w-4 text-brand-400 mt-0.5 shrink-0" />
                                                <div className="min-w-0">
                                                    <p className="font-medium text-white text-sm truncate">{loc.name}</p>
                                                    {loc.address && <p className="text-xs text-gray-500 mt-0.5 truncate">{loc.address}</p>}
                                                    <p className="text-xs text-gray-600 truncate">{[loc.city, loc.state, loc.country].filter(Boolean).join(', ') || '—'}</p>
                                                    <span className="inline-block mt-2 text-[10px] bg-brand-500/10 px-1.5 py-0.5 rounded text-brand-400 border border-brand-500/10">
                                                        🔑 {loc.key_capacity || 0} key slots
                                                    </span>
                                                </div>
                                            </div>
                                            <button
                                                onClick={(e) => handleDelete(loc, e)}
                                                className="p-1.5 rounded-lg hover:bg-red-500/10 text-gray-600 hover:text-red-400 transition-colors shrink-0"
                                                title="Delete location"
                                            >
                                                <Trash2 className="h-3.5 w-3.5" />
                                            </button>
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </Card>
                    ))}
                </div>
            )}

            <Modal isOpen={showModal} onClose={() => { setShowModal(false); setFormData(emptyForm); }} title="Add Location">
                <form onSubmit={handleCreate} className="space-y-4">
                    <div className="space-y-1.5">
                        <label className="block text-sm font-medium text-gray-300">Company</label>
                        <div className="relative">
                            <Building2 className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500" />
                            <select
                                required
                                value={formData.valet_company_id}
                                onChange={(e) => setFormData({ ...formData, valet_company_id: e.target.value })}
                                className="block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-4 text-gray-200 ring-1 ring-inset ring-white/5 focus:ring-2 focus:ring-brand-500/50 text-sm transition-all"
                            >
                                <option value="">Select a company</option>
                                {companies.map(c => <option key={c.id} value={c.id}>{c.company_name}</option>)}
                            </select>
                        </div>
                    </div>
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
                        <Button variant="ghost" type="button" onClick={() => { setShowModal(false); setFormData(emptyForm); }}>Cancel</Button>
                        <Button type="submit" disabled={saving}>{saving ? 'Adding...' : 'Add Location'}</Button>
                    </div>
                </form>
            </Modal>
        </div>
    );
};

export default AdminLocations;
