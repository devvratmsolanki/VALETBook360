import { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import { Phone, User, Car as CarIcon, Camera, MapPin, Wrench, Search, UserCheck, Timer, Send, Clock, RefreshCw, Check } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Select from '../../components/ui/Select';
import Modal from '../../components/ui/Modal';
import { toast } from '../../components/ui/Toast';
import { useAuth } from '../../contexts/AuthContext';
import { searchVisitorByPhone, getVisitorByPhone, createVisitor } from '../../services/visitorService';
import { findCarByNumber, createCar } from '../../services/carService';
import { createTransaction, getActiveTransactions, subscribeToTransactions, updateTransactionStatus, assignDriverForRetrieval, getNextAvailableKeySlot } from '../../services/transactionService';
import { getDriversByCompany } from '../../services/driverService';
import { getLocationsByCompany } from '../../services/locationService';
import { sendCarParked, sendDriverAssigned, sendCarReady, sendCarDelivered } from '../../services/webhookService';
import { formatTime, parseUTC } from '../../lib/utils';

// ─── Live Timer Component ───
const LiveTimer = ({ since }) => {
    const [elapsed, setElapsed] = useState('');
    useEffect(() => {
        const calc = () => {
            const parsed = parseUTC(since);
            const diff = Math.max(0, Math.floor((Date.now() - parsed.getTime()) / 1000));
            const m = Math.floor(diff / 60);
            const s = diff % 60;
            setElapsed(`${m}:${s.toString().padStart(2, '0')}`);
        };
        calc();
        const id = setInterval(calc, 1000);
        return () => clearInterval(id);
    }, [since]);
    return <span className="font-mono text-xs">{elapsed}</span>;
};

// ─── Tile color config based on status ───
const tileStyles = {
    requested: { bg: 'bg-red-500/10', border: 'border-red-500/30', glow: 'shadow-red-500/10', text: 'text-red-400', dot: 'bg-red-500' },
    retrieving: { bg: 'bg-amber-500/10', border: 'border-amber-500/30', glow: 'shadow-amber-500/10', text: 'text-amber-400', dot: 'bg-amber-500' },
    ready: { bg: 'bg-emerald-500/10', border: 'border-emerald-500/30', glow: 'shadow-emerald-500/10', text: 'text-emerald-400', dot: 'bg-emerald-500' },
    delivered: { bg: 'bg-gray-500/5', border: 'border-gray-500/20', glow: '', text: 'text-gray-500', dot: 'bg-gray-500' },
    parked: { bg: 'bg-blue-500/5', border: 'border-blue-500/20', glow: '', text: 'text-blue-400', dot: 'bg-blue-500' },
};

const OperatorDashboard = () => {
    const { companyId, companyName, locationId, locationName, role } = useAuth();

    // ─── Check-in form state ───
    const [countryCode, setCountryCode] = useState('+91');
    const [phone, setPhone] = useState('');
    const [name, setName] = useState('');
    const [carNumber, setCarNumber] = useState('');
    const [carMake, setCarMake] = useState('');
    const [parkingLocation, setParkingLocation] = useState('');
    const [selectedDriver, setSelectedDriver] = useState('');
    const [selectedLocationId, setSelectedLocationId] = useState(() => localStorage.getItem('vb360_last_location') || '');
    const [loading, setLoading] = useState(false);
    const [searchResults, setSearchResults] = useState([]);
    const [showDropdown, setShowDropdown] = useState(false);
    const [existingVisitor, setExistingVisitor] = useState(null);
    const [isReturning, setIsReturning] = useState(false);
    const [keyCode, setKeyCode] = useState('');
    const [locationCapacity, setLocationCapacity] = useState(0);
    const dropdownRef = useRef(null);
    const fileInputRef = useRef(null);
    const keyInputRef = useRef(null);

    // ─── Right panel state ───
    const [transactions, setTransactions] = useState([]);
    const [drivers, setDrivers] = useState([]);
    const [locations, setLocations] = useState([]);
    const [txLoading, setTxLoading] = useState(true);
    const [refreshing, setRefreshing] = useState(false);
    const [showHistory, setShowHistory] = useState(false);

    // ─── Assignment modal ───
    const [showAssignModal, setShowAssignModal] = useState(false);
    const [selectedTx, setSelectedTx] = useState(null);
    const [assignDriverId, setAssignDriverId] = useState('');
    const [etaMinutes, setEtaMinutes] = useState(8);
    const [assigning, setAssigning] = useState(false);

    // ─── Fetch all data ───
    const fetchAll = useCallback(async () => {
        try {
            const [txs, driverList, locationList] = await Promise.all([
                getActiveTransactions(companyId),
                companyId ? getDriversByCompany(companyId) : [],
                companyId ? getLocationsByCompany(companyId) : [],
            ]);
            setTransactions(txs);
            setDrivers(driverList.filter(d => d.active));
            setLocations(locationList);

            // Re-fetch next available slot if location is selected
            if (selectedLocationId) {
                const nextSlot = await getNextAvailableKeySlot(selectedLocationId);
                if (nextSlot) {
                    setKeyCode(nextSlot);
                }
                const loc = locationList.find(l => l.id === selectedLocationId);
                if (loc) setLocationCapacity(loc.key_capacity || 0);
            }
        } catch (err) {
            console.error('Fetch error:', err);
        } finally {
            setTxLoading(false);
            setRefreshing(false);
        }
    }, [companyId, selectedLocationId]);

    const handleRefresh = useCallback(() => {
        setRefreshing(true);
        fetchAll();
    }, [fetchAll]);

    useEffect(() => {
        fetchAll();
        const sub = subscribeToTransactions(() => fetchAll());

        // 30-second auto-refresh heartbeat
        const heartbeat = setInterval(() => {
            fetchAll();
        }, 30000);

        return () => {
            sub.unsubscribe();
            clearInterval(heartbeat);
        };
    }, [fetchAll]);

    // ─── Phone search ───
    useEffect(() => {
        const digits = phone.replace(/\D/g, '');
        if (digits.length < 7) { setSearchResults([]); setShowDropdown(false); return; }
        const fullPhone = countryCode + digits;
        const t = setTimeout(async () => {
            try {
                const r = await searchVisitorByPhone(fullPhone);
                setSearchResults(r);
                setShowDropdown(r.length > 0);
            } catch (err) {
                console.error('[Supabase Search Error]', err);
            }
        }, 300);
        return () => clearTimeout(t);
    }, [phone, countryCode]);

    useEffect(() => {
        const h = (e) => { if (dropdownRef.current && !dropdownRef.current.contains(e.target)) setShowDropdown(false); };
        document.addEventListener('mousedown', h);
        return () => document.removeEventListener('mousedown', h);
    }, []);

    const selectVisitor = async (v) => {
        setPhone(v.phone); setName(v.name); setExistingVisitor(v); setIsReturning(true); setShowDropdown(false);
        try {
            const full = await getVisitorByPhone(v.phone);
            if (full?.cars?.length > 0) {
                const c = full.cars[full.cars.length - 1];
                setCarNumber(c.car_number || '');
                setCarMake(`${c.make || ''} ${c.model || ''}`.trim());
            }
        } catch { }
    };

    useEffect(() => {
        if (role === 'valet' && locationId) {
            handleLocationChange(locationId);
        } else if (selectedLocationId && locations.length > 0) {
            handleLocationChange(selectedLocationId);
        }
    }, [locations.length, locationId, role]);

    const handleLocationChange = async (val) => {
        setSelectedLocationId(val);
        if (val) {
            localStorage.setItem('vb360_last_location', val);
            try {
                // 1. Get capacity
                const loc = locations.find(l => l.id === val);
                if (loc) setLocationCapacity(loc.key_capacity || 0);

                // 2. Get next slot
                const nextSlot = await getNextAvailableKeySlot(val);
                if (nextSlot) {
                    setKeyCode(nextSlot);
                } else {
                    toast.warning('Location key capacity reached!');
                    setKeyCode('');
                }
            } catch (err) {
                console.error('Error fetching key slot:', err);
            }
        } else {
            setLocationCapacity(0);
            setKeyCode('');
        }
    };

    // ─── Check-in submit ───
    const handleSubmit = async (e) => {
        e.preventDefault();
        const phoneDigits = phone.replace(/\D/g, '');
        if (phoneDigits.length < 10) return toast.error('Phone must have at least 10 digits');
        // Strip leading country code if user accidentally typed it (e.g. 919876... with +91 selected)
        const codeDigits = countryCode.replace(/\D/g, '');
        const cleanedDigits = phoneDigits.startsWith(codeDigits) && phoneDigits.length > 10
            ? phoneDigits.slice(codeDigits.length)
            : phoneDigits;
        const fullPhone = countryCode + cleanedDigits;
        // Validate name
        if (!name || name.trim().length < 2) return toast.error('Guest name must be at least 2 characters');
        // Validate car number: at least 4 chars, must have letters and digits
        const cleanCar = carNumber.replace(/\s/g, '');
        if (cleanCar.length < 4) return toast.error('Car number must be at least 4 characters');
        if (!/[A-Z]/.test(cleanCar) || !/\d/.test(cleanCar)) return toast.error('Car number must contain letters and digits (e.g. MH01AB1234)');
        // Validate driver
        if (!selectedDriver) return toast.error('Please select a driver');
        setLoading(true);
        try {
            let visitorId = existingVisitor?.id;
            if (!visitorId) {
                // Final check by phone to avoid duplicate key error
                const existing = await getVisitorByPhone(fullPhone);
                if (existing) {
                    visitorId = existing.id;
                } else {
                    const nv = await createVisitor({ name, phone: fullPhone });
                    visitorId = nv.id;
                }
            }

            let carId;
            const existing = await findCarByNumber(carNumber.toUpperCase());
            if (existing) { carId = existing.id; } else {
                const [make, ...mp] = (carMake || '').split(' ');
                const nc = await createCar({ car_number: carNumber.toUpperCase(), visitor_id: visitorId, make: make || null, model: mp.join(' ') || null });
                carId = nc.id;
            }

            if (selectedLocationId) {
                const checkSlot = await getNextAvailableKeySlot(selectedLocationId);
                if (!checkSlot && !keyCode) return toast.error('No key slots available at this location');
            }

            const txData = { visitor_id: visitorId, car_id: carId, parking_slot: parkingLocation || null, key_code: keyCode || null, status: 'parked', valet_company_id: companyId || null };
            if (selectedDriver) txData.parked_by_driver_id = selectedDriver;
            if (selectedLocationId) txData.location_id = selectedLocationId;
            const newTx = await createTransaction(txData);

            // Workflow 1: WhatsApp → Car Parked
            const driverObj = drivers.find(d => d.id === selectedDriver);
            const locationObj = locations.find(l => l.id === selectedLocationId);
            sendCarParked({
                guest_name: name,
                phone: fullPhone,
                car_number: carNumber.toUpperCase(),
                parking_slot: parkingLocation,
                driver_name: driverObj?.name,
                driver_id: driverObj?.staff_id || driverObj?.id?.slice(0, 8),
                company_name: companyName,
                transaction_id: newTx.id,
            });

            toast.success('Vehicle parked!');
            setPhone(''); setName(''); setCarNumber(''); setCarMake(''); setParkingLocation(''); setKeyCode(''); setSelectedDriver(''); setExistingVisitor(null); setIsReturning(false);
            fetchAll();
        } catch (err) {
            toast.error(err.message || 'Check-in failed');
        } finally { setLoading(false); }
    };

    // ─── Right panel: retrieval actions ───
    const openAssignModal = (tx) => {
        setSelectedTx(tx); setAssignDriverId(tx.parked_by_driver_id || ''); setEtaMinutes(8); setShowAssignModal(true);
    };

    const handleAssignDriver = async () => {
        if (!assignDriverId) return toast.error('Select a driver');
        setAssigning(true);
        try {
            await assignDriverForRetrieval(selectedTx.id, assignDriverId, etaMinutes);

            // Template 3: WhatsApp → Driver Assigned
            const d = drivers.find(dr => dr.id === assignDriverId);
            const loc = locations.find(l => l.id === selectedTx.location_id);
            sendDriverAssigned({
                phone: selectedTx.visitors?.phone,
                driver_name: d?.name,
                driver_id: d?.staff_id || d?.id?.slice(0, 8),
                location_name: loc?.name || 'N/A',
                eta_minutes: etaMinutes,
            });

            toast.success(`Driver assigned! ETA: ${etaMinutes} min`);
            setShowAssignModal(false); setSelectedTx(null); fetchAll();
        } catch { toast.error('Assignment failed'); } finally { setAssigning(false); }
    };

    const handleStatus = async (id, status) => {
        try {
            await updateTransactionStatus(id, status);
            const tx = transactions.find(t => t.id === id);

            // Template 4: WhatsApp → Car Ready
            if (status === 'ready' && tx) {
                const loc = locations.find(l => l.id === tx.location_id);
                sendCarReady({
                    phone: tx.visitors?.phone,
                    car_number: tx.cars?.car_number,
                    location_name: loc?.name || 'N/A',
                });
            }

            // Template 5: WhatsApp → Car Delivered
            if (status === 'delivered' && tx) {
                sendCarDelivered({
                    phone: tx.visitors?.phone,
                    car_number: tx.cars?.car_number,
                    company_name: companyName,
                });
            }

            toast.success(`${status}`);
            fetchAll();
        } catch { toast.error('Update failed'); }
    };

    // ─── Grouped cards for right panel ───
    const requestedCards = useMemo(() => transactions.filter(t => t.status === 'requested' && !t.retrieved_by_driver_id).sort((a, b) => new Date(a.created_at) - new Date(b.created_at)), [transactions]);
    const retrievingCards = useMemo(() => transactions.filter(t => t.status === 'requested' && !!t.retrieved_by_driver_id).sort((a, b) => new Date(a.created_at) - new Date(b.created_at)), [transactions]);
    const readyCards = useMemo(() => transactions.filter(t => t.status === 'ready').sort((a, b) => new Date(a.created_at) - new Date(b.created_at)), [transactions]);
    const parkedCards = useMemo(() => transactions.filter(t => t.status === 'parked').sort((a, b) => new Date(a.created_at) - new Date(b.created_at)), [transactions]);

    const deliveredCars = useMemo(() => transactions.filter(t => t.status === 'delivered').sort((a, b) => new Date(b.created_at) - new Date(a.created_at)), [transactions]);

    const counts = useMemo(() => ({
        parked: transactions.filter(t => t.status === 'parked').length,
        requested: transactions.filter(t => t.status === 'requested').length,
        ready: transactions.filter(t => t.status === 'ready').length,
        delivered: deliveredCars.length,
    }), [transactions, deliveredCars]);

    const driverOptions = [{ value: '', label: 'Select driver... *' }, ...drivers.map(d => ({ value: d.id, label: d.name }))];
    const locationOptions = [{ value: '', label: 'Select location...' }, ...locations.map(l => ({ value: l.id, label: l.name }))];

    // ─── Render a single car tile ───
    const renderTile = (tx) => {
        // Determine visual state: requested + driver assigned = "retrieving" (yellow)
        const isParked = tx.status === 'parked';
        const isReady = tx.status === 'ready';
        const isDelivered = tx.status === 'delivered';
        const isRequested = tx.status === 'requested' && !tx.retrieved_by_driver_id;
        const isRetrieving = tx.status === 'requested' && !!tx.retrieved_by_driver_id;

        const visualStatus = isRetrieving ? 'retrieving' : tx.status;
        const style = tileStyles[visualStatus] || tileStyles.parked;

        return (
            <div key={tx.id} className={`rounded-xl border p-3.5 transition-all duration-300 ${style.bg} ${style.border} ${style.glow ? `shadow-lg ${style.glow}` : ''} ${isRequested ? 'animate-pulse-slow' : ''}`}>
                <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                            <span className={`h-2 w-2 rounded-full ${style.dot} ${isRequested ? 'animate-ping-slow' : ''}`} />
                            <span className="text-base font-extrabold text-white tracking-wide truncate">{tx.cars?.car_number || '—'}</span>
                            {tx.cars?.make && <span className="text-[10px] text-gray-500 hidden sm:inline">{tx.cars.make}</span>}
                        </div>
                        <p className="text-xs text-gray-400 mt-1 truncate">{tx.visitors?.name || 'Guest'} • {tx.visitors?.phone || ''}</p>
                        <div className="flex items-center gap-2 mt-1.5 flex-wrap">
                            {tx.parking_slot && <span className="text-[10px] bg-white/5 px-1.5 py-0.5 rounded text-gray-400">📍 {tx.parking_slot}</span>}
                            {tx.key_code && <span className="text-[10px] bg-brand-500/10 px-1.5 py-0.5 rounded text-brand-400">🔑 {tx.key_code}</span>}
                            {tx.locations?.name && <span className="text-[10px] bg-purple-500/10 px-1.5 py-0.5 rounded text-purple-400">📌 {tx.locations.name}</span>}
                            {tx.parked_driver && <span className="text-[10px] text-blue-400">🅿 {tx.parked_driver.name}</span>}
                            {tx.retrieved_driver && <span className="text-[10px] text-amber-400">🚗 {tx.retrieved_driver.name}</span>}
                        </div>
                    </div>
                    <div className="flex flex-col items-end gap-1.5 shrink-0">
                        <div className={`flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-semibold uppercase tracking-wider ${style.bg} ${style.text}`}>
                            <Timer className="h-3 w-3" />
                            <LiveTimer since={tx.requested_at || tx.updated_at || tx.created_at} />
                        </div>

                        {isParked && (
                            <button onClick={() => openAssignModal(tx)} className="text-[10px] px-2.5 py-1 rounded-lg bg-blue-500/10 text-blue-400 hover:bg-blue-500/20 border border-blue-500/20 transition-all font-medium flex items-center gap-1">
                                <Send className="h-3 w-3" /> Retrieve
                            </button>
                        )}
                        {isRequested && (
                            <button onClick={() => openAssignModal(tx)} className="text-[10px] px-2.5 py-1 rounded-lg bg-amber-500/10 text-amber-400 hover:bg-amber-500/20 border border-amber-500/20 transition-all font-medium animate-pulse flex items-center gap-1">
                                <UserCheck className="h-3 w-3" /> Assign Driver
                            </button>
                        )}
                        {isRetrieving && (
                            <button onClick={() => handleStatus(tx.id, 'ready')} className="text-[10px] px-2.5 py-1 rounded-lg bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20 border border-emerald-500/20 transition-all font-medium flex items-center gap-1">
                                <Check className="h-3 w-3" /> Car Ready
                            </button>
                        )}
                        {isReady && (
                            <button onClick={() => handleStatus(tx.id, 'delivered')} className="text-[10px] px-2.5 py-1 rounded-lg bg-gray-500/10 text-gray-300 hover:bg-gray-500/20 border border-gray-500/20 transition-all font-medium flex items-center gap-1">
                                <Check className="h-3 w-3" /> Delivered
                            </button>
                        )}
                    </div>
                </div>
            </div>
        );
    };

    return (
        <div className="animate-fade-in">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">

                {/* ═══ LEFT: Check-In Form ═══ */}
                <div>
                    <div className="mb-5">
                        <h1 className="text-xl font-bold text-white">Park Vehicle</h1>
                        <p className="text-xs text-gray-500 mt-0.5">Register new arrival</p>
                    </div>
                    <Card className="p-5 relative overflow-hidden">
                        <div className="absolute top-0 left-0 w-full h-px bg-gradient-to-r from-transparent via-brand-500/30 to-transparent" />
                        <form onSubmit={handleSubmit} className="space-y-4">
                            {/* Location */}
                            {locations.length > 0 && (
                                role === 'valet' && locationId ? (
                                    <div className="bg-brand-500/5 border border-brand-500/20 rounded-xl p-3 flex items-center gap-3">
                                        <div className="bg-brand-500/10 p-2 rounded-lg">
                                            <MapPin className="h-4 w-4 text-brand-400" />
                                        </div>
                                        <div>
                                            <p className="text-[10px] text-gray-500 uppercase tracking-wider font-semibold">Assigned Post</p>
                                            <p className="text-sm font-bold text-white uppercase">{locationName || "Assigned Location"}</p>
                                        </div>
                                    </div>
                                ) : (
                                    <Select label={<span className="flex items-center gap-2 text-xs"><MapPin className="h-3.5 w-3.5 text-brand-500" /> Service Location</span>}
                                        options={locationOptions} value={selectedLocationId} onChange={(e) => handleLocationChange(e.target.value)} />
                                )
                            )}

                            {/* Phone */}
                            <div className="space-y-1" ref={dropdownRef}>
                                <label className="flex items-center gap-2 text-xs font-medium text-gray-300">
                                    <Phone className="h-3.5 w-3.5 text-brand-500" /> Phone <span className="text-red-400">*</span>
                                    <span className="text-[10px] text-gray-600 ml-auto">Search after 7 digits</span>
                                </label>
                                <div className="relative">
                                    <div className="flex gap-1.5">
                                        <select value={countryCode} onChange={(e) => setCountryCode(e.target.value)}
                                            className="w-[88px] shrink-0 rounded-xl border-0 bg-dark-600 py-2.5 px-2 text-sm text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 transition-all appearance-none cursor-pointer">
                                            <option value="+91">🇮🇳 +91</option>
                                            <option value="+1">🇺🇸 +1</option>
                                            <option value="+44">🇬🇧 +44</option>
                                            <option value="+971">🇦🇪 +971</option>
                                            <option value="+966">🇸🇦 +966</option>
                                            <option value="+65">🇸🇬 +65</option>
                                            <option value="+61">🇦🇺 +61</option>
                                            <option value="+81">🇯🇵 +81</option>
                                            <option value="+49">🇩🇪 +49</option>
                                            <option value="+33">🇫🇷 +33</option>
                                        </select>
                                        <div className="relative group flex-1">
                                            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-gray-500" />
                                            <input type="tel" value={phone} onChange={(e) => { setPhone(e.target.value.replace(/\D/g, '')); setExistingVisitor(null); setIsReturning(false); }}
                                                placeholder="9876543210" required maxLength={10} className="block w-full rounded-xl border-0 bg-dark-600 py-2.5 pl-9 pr-3 text-sm text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 transition-all" />
                                        </div>
                                    </div>
                                    {showDropdown && (
                                        <div className="absolute z-20 w-full mt-1 bg-dark-700 border border-white/10 rounded-xl shadow-2xl overflow-hidden">
                                            {searchResults.map(v => (
                                                <button key={v.id} type="button" onClick={() => selectVisitor(v)} className="w-full px-3 py-2.5 text-left hover:bg-brand-500/10 border-b border-white/5 last:border-0">
                                                    <p className="text-sm font-medium text-white">{v.name}</p><p className="text-xs text-gray-400">{v.phone}</p>
                                                </button>
                                            ))}
                                        </div>
                                    )}
                                </div>
                                {isReturning && <p className="text-[10px] text-emerald-400">✓ Returning visitor</p>}
                            </div>

                            {/* Name */}
                            <div className="space-y-1">
                                <label className="flex items-center gap-2 text-xs font-medium text-gray-300"><User className="h-3.5 w-3.5 text-brand-500" /> Guest Name <span className="text-red-400">*</span></label>
                                <div className="relative group">
                                    <User className="absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-gray-500" />
                                    <input type="text" value={name} onChange={(e) => setName(e.target.value)} placeholder="Guest name" required className="block w-full rounded-xl border-0 bg-dark-600 py-2.5 pl-9 pr-3 text-sm text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 transition-all" />
                                </div>
                            </div>

                            {/* Car Number */}
                            <div className="space-y-1">
                                <label className="flex items-center gap-2 text-xs font-medium text-gray-300"><CarIcon className="h-3.5 w-3.5 text-brand-500" /> Car Number <span className="text-red-400">*</span></label>
                                <div className="flex gap-2">
                                    <div className="relative group flex-1">
                                        <CarIcon className="absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-gray-500" />
                                        <input type="text" value={carNumber} onChange={(e) => setCarNumber(e.target.value.toUpperCase())} placeholder="MH01AB1234" required className="block w-full rounded-xl border-0 bg-dark-600 py-2.5 pl-9 pr-3 text-sm text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 transition-all uppercase" />
                                    </div>
                                    <button type="button" onClick={() => fileInputRef.current?.click()} className="px-3 py-2.5 rounded-xl bg-dark-600 border border-white/5 text-gray-400 hover:text-brand-400 transition-all">
                                        <Camera className="h-4 w-4" />
                                    </button>
                                    <input ref={fileInputRef} type="file" accept="image/*" capture="environment" className="hidden" />
                                </div>
                            </div>

                            {/* Car Make */}
                            <div className="space-y-1">
                                <label className="flex items-center gap-2 text-xs font-medium text-gray-300"><Wrench className="h-3.5 w-3.5 text-gray-500" /> Make / Model <span className="text-gray-600 text-[10px]">(optional)</span></label>
                                <div className="relative group">
                                    <Wrench className="absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-gray-500" />
                                    <input type="text" value={carMake} onChange={(e) => setCarMake(e.target.value)} placeholder="Toyota Camry" className="block w-full rounded-xl border-0 bg-dark-600 py-2.5 pl-9 pr-3 text-sm text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 transition-all" />
                                </div>
                            </div>

                            {/* Parking Slot */}
                            <div className="space-y-1">
                                <label className="flex items-center gap-2 text-xs font-medium text-gray-300"><MapPin className="h-3.5 w-3.5 text-gray-500" /> Parking Slot <span className="text-gray-600 text-[10px]">(optional)</span></label>
                                <div className="relative group">
                                    <MapPin className="absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-gray-500" />
                                    <input type="text" value={parkingLocation} onChange={(e) => setParkingLocation(e.target.value)} placeholder="B2-Slot 14" className="block w-full rounded-xl border-0 bg-dark-600 py-2.5 pl-9 pr-3 text-sm text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 transition-all" />
                                </div>
                            </div>

                            {/* Key Code */}
                            <div className="space-y-1">
                                <label className="flex items-center justify-between text-xs font-medium text-gray-300">
                                    <span className="flex items-center gap-2">🔑 Key Code <span className="text-red-400">*</span></span>
                                    {locationCapacity > 0 && <span className="text-[10px] text-gray-500 font-normal">Total Slots: {locationCapacity}</span>}
                                </label>
                                <div className="flex gap-2">
                                    <div className={`flex-1 flex items-center gap-3 rounded-xl border p-2.5 transition-all ${keyCode ? 'bg-brand-500/5 border-brand-500/30' : 'bg-dark-600 border-white/5'}`}>
                                        <div className={`h-8 w-8 rounded-lg flex items-center justify-center text-sm font-bold border ${keyCode ? 'bg-brand-500 text-black border-brand-400 shadow-lg shadow-brand-500/20' : 'bg-dark-700 text-gray-600 border-white/5'}`}>
                                            {keyCode || '?'}
                                        </div>
                                        <div className="flex-1">
                                            <p className={`text-sm font-medium ${keyCode ? 'text-brand-400' : 'text-gray-500'}`}>
                                                {keyCode ? `Assigned Slot #${keyCode}` : 'Detecting Slot...'}
                                            </p>
                                            <p className="text-[10px] text-gray-600">Auto-filled based on capacity</p>
                                        </div>
                                        {selectedLocationId && (
                                            <button type="button" onClick={() => handleLocationChange(selectedLocationId)} className="p-1.5 rounded-lg hover:bg-white/5 text-gray-500 hover:text-white transition-colors" title="Re-calculate slot">
                                                <RefreshCw className="h-3.5 w-3.5" />
                                            </button>
                                        )}
                                    </div>
                                </div>
                                <input type="hidden" value={keyCode} required />
                            </div>

                            {/* Driver */}
                            <Select label={<span className="flex items-center gap-2 text-xs"><UserCheck className="h-3.5 w-3.5 text-brand-500" /> Driver <span className="text-red-400">*</span></span>}
                                options={driverOptions} value={selectedDriver} onChange={(e) => setSelectedDriver(e.target.value)} />

                            <Button type="submit" size="lg" className="w-full" disabled={loading}>
                                {loading ? <span className="flex items-center gap-2"><svg className="animate-spin h-4 w-4" viewBox="0 0 24 24"><circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" /><path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" /></svg> Parking...</span>
                                    : <span className="flex items-center gap-2"><CarIcon className="h-4 w-4" /> Park Vehicle</span>}
                            </Button>
                        </form>
                    </Card>
                </div>

                {/* ═══ RIGHT: Car Retrieval Panel ═══ */}
                <div>
                    <div className="flex items-center justify-between mb-5">
                        <div>
                            <h1 className="text-xl font-bold text-white">Cars</h1>
                            <p className="text-xs text-gray-500 mt-0.5">
                                {counts.parked} parked • {counts.requested} requested • {counts.ready} ready
                            </p>
                        </div>
                        <button onClick={handleRefresh} disabled={refreshing} className="p-2 rounded-xl hover:bg-white/5 text-gray-400 hover:text-white transition-colors disabled:opacity-50">
                            <RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />
                        </button>
                    </div>

                    {/* Mini stat pills */}
                    <div className="flex gap-2 mb-4">
                        {[
                            { label: 'Parked', count: counts.parked, color: 'text-blue-400 bg-blue-500/10' },
                            { label: 'Requested', count: counts.requested, color: 'text-red-400 bg-red-500/10' },
                            { label: 'Ready', count: counts.ready, color: 'text-emerald-400 bg-emerald-500/10' },
                        ].map(s => (
                            <div key={s.label} className={`flex-1 text-center py-2 rounded-xl text-xs font-semibold ${s.color}`}>
                                <span className="text-base">{s.count}</span>
                                <p className="text-[10px] mt-0.5 opacity-70">{s.label}</p>
                            </div>
                        ))}
                        <button onClick={() => setShowHistory(!showHistory)}
                            className={`flex-1 text-center py-2 rounded-xl text-xs font-semibold transition-all ${showHistory ? 'text-white bg-gray-500/20 ring-1 ring-gray-500/30' : 'text-gray-400 bg-gray-500/10 hover:bg-gray-500/15'}`}>
                            <span className="text-base">{counts.delivered}</span>
                            <p className="text-[10px] mt-0.5 opacity-70">Done</p>
                        </button>
                    </div>

                    {/* ─── SECTIONED TILES ─── */}
                    {txLoading ? (
                        <Card className="p-8 text-center"><div className="animate-spin h-6 w-6 border-2 border-brand-500 border-t-transparent rounded-full mx-auto" /></Card>
                    ) : (requestedCards.length + retrievingCards.length + readyCards.length + parkedCards.length) === 0 ? (
                        <Card className="p-8 text-center"><CarIcon className="h-8 w-8 text-gray-600 mx-auto mb-2" /><p className="text-gray-500 text-sm">No active cars</p></Card>
                    ) : (
                        <div className="space-y-4 max-h-[calc(100vh-320px)] overflow-y-auto pr-1 scrollbar-thin">
                            {/* 🔴 REQUESTED — Primary section */}
                            {requestedCards.length > 0 && (
                                <div>
                                    <div className="flex items-center gap-2 mb-2">
                                        <span className="h-2 w-2 rounded-full bg-red-500 animate-ping-slow" />
                                        <h3 className="text-xs font-bold text-red-400 uppercase tracking-wider">Requested ({requestedCards.length})</h3>
                                    </div>
                                    <div className="space-y-2">{requestedCards.map(renderTile)}</div>
                                </div>
                            )}

                            {/* 🟡 RETRIEVING */}
                            {retrievingCards.length > 0 && (
                                <div>
                                    <div className="flex items-center gap-2 mb-2">
                                        <span className="h-2 w-2 rounded-full bg-amber-500" />
                                        <h3 className="text-xs font-bold text-amber-400 uppercase tracking-wider">Retrieving ({retrievingCards.length})</h3>
                                    </div>
                                    <div className="space-y-2">{retrievingCards.map(renderTile)}</div>
                                </div>
                            )}

                            {/* 🟢 READY */}
                            {readyCards.length > 0 && (
                                <div>
                                    <div className="flex items-center gap-2 mb-2">
                                        <span className="h-2 w-2 rounded-full bg-emerald-500" />
                                        <h3 className="text-xs font-bold text-emerald-400 uppercase tracking-wider">Ready ({readyCards.length})</h3>
                                    </div>
                                    <div className="space-y-2">{readyCards.map(renderTile)}</div>
                                </div>
                            )}

                            {/* 🔵 PARKED */}
                            {parkedCards.length > 0 && (
                                <div>
                                    <div className="flex items-center gap-2 mb-2">
                                        <span className="h-2 w-2 rounded-full bg-blue-500" />
                                        <h3 className="text-xs font-bold text-blue-400 uppercase tracking-wider">Parked ({parkedCards.length})</h3>
                                    </div>
                                    <div className="space-y-2">{parkedCards.map(renderTile)}</div>
                                </div>
                            )}
                        </div>
                    )}

                    {/* Delivered history */}
                    {showHistory && deliveredCars.length > 0 && (
                        <div className="mt-4">
                            <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3 flex items-center gap-2">
                                <Clock className="h-3.5 w-3.5" /> Delivered Today ({deliveredCars.length})
                            </h3>
                            <div className="space-y-2 max-h-80 overflow-y-auto pr-1">
                                {deliveredCars.map(tx => (
                                    <div key={tx.id} className="rounded-xl border border-gray-500/20 bg-gray-500/5 p-3">
                                        <div className="flex items-start justify-between">
                                            <div>
                                                <div className="flex items-center gap-2">
                                                    <span className="h-2 w-2 rounded-full bg-gray-500" />
                                                    <span className="text-sm font-bold text-gray-300">{tx.cars?.car_number || '—'}</span>
                                                    {tx.cars?.make && <span className="text-[10px] text-gray-500">{tx.cars.make}</span>}
                                                </div>
                                                <p className="text-xs text-gray-500 mt-1">{tx.visitors?.name} • {tx.visitors?.phone}</p>
                                                <div className="flex items-center gap-2 mt-1.5 flex-wrap">
                                                    {tx.locations?.name && <span className="text-[10px] bg-purple-500/10 px-1.5 py-0.5 rounded text-purple-400">{tx.locations.name}</span>}
                                                    {tx.parked_driver && <span className="text-[10px] text-blue-400">🅿 {tx.parked_driver.name}</span>}
                                                    {tx.retrieved_driver && <span className="text-[10px] text-amber-400">🚗 {tx.retrieved_driver.name}</span>}
                                                </div>
                                            </div>
                                            <span className="text-[10px] text-gray-600">{formatTime(tx.created_at)}</span>
                                        </div>
                                        {/* Timeline */}
                                        <div className="mt-2.5 pt-2 border-t border-white/5 grid grid-cols-4 gap-1 text-[9px]">
                                            <div className="text-center">
                                                <p className="text-blue-400 font-semibold">Parked</p>
                                                <p className="text-gray-500">{tx.created_at ? formatTime(tx.created_at) : '—'}</p>
                                            </div>
                                            <div className="text-center">
                                                <p className="text-red-400 font-semibold">Requested</p>
                                                <p className="text-gray-500">{tx.requested_at ? formatTime(tx.requested_at) : '—'}</p>
                                            </div>
                                            <div className="text-center">
                                                <p className="text-emerald-400 font-semibold">Ready</p>
                                                <p className="text-gray-500">{tx.ready_at ? formatTime(tx.ready_at) : '—'}</p>
                                            </div>
                                            <div className="text-center">
                                                <p className="text-gray-300 font-semibold">Delivered</p>
                                                <p className="text-gray-500">{tx.delivered_at ? formatTime(tx.delivered_at) : '—'}</p>
                                            </div>
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </div>
                    )}
                    {showHistory && deliveredCars.length === 0 && (
                        <Card className="mt-4 p-6 text-center"><CarIcon className="h-6 w-6 text-gray-600 mx-auto mb-2" /><p className="text-gray-500 text-xs">No delivered cars yet</p></Card>
                    )}
                </div>
            </div>

            {/* ═══ Driver Assignment Modal ═══ */}
            <Modal isOpen={showAssignModal} onClose={() => setShowAssignModal(false)} title="Assign Driver for Retrieval">
                {selectedTx && (
                    <div className="space-y-4">
                        <div className="bg-dark-600 rounded-xl p-4">
                            <p className="text-sm font-medium text-white">{selectedTx.cars?.car_number}</p>
                            <p className="text-xs text-gray-400 mt-1">Guest: {selectedTx.visitors?.name} • {selectedTx.visitors?.phone}</p>
                            {selectedTx.parked_driver && <p className="text-xs text-blue-400 mt-1">Parked by: {selectedTx.parked_driver.name}</p>}
                        </div>
                        <div className="space-y-1.5">
                            <label className="text-sm font-medium text-gray-300 flex items-center gap-2"><UserCheck className="h-3.5 w-3.5 text-brand-500" /> Select Driver</label>
                            <select value={assignDriverId} onChange={(e) => setAssignDriverId(e.target.value)}
                                className="block w-full rounded-xl border-0 bg-dark-600 py-3 pl-4 pr-10 text-sm text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 transition-all">
                                <option value="">Select...</option>
                                {drivers.map(d => <option key={d.id} value={d.id}>{d.name}{d.id === selectedTx.parked_by_driver_id ? ' (same ✓)' : ''}</option>)}
                            </select>
                        </div>
                        <div className="space-y-1.5">
                            <label className="text-sm font-medium text-gray-300 flex items-center gap-2"><Timer className="h-3.5 w-3.5 text-brand-500" /> ETA (minutes)</label>
                            <input type="number" min="1" max="60" value={etaMinutes} onChange={(e) => setEtaMinutes(parseInt(e.target.value) || 8)}
                                className="block w-full rounded-xl border-0 bg-dark-600 py-3 px-4 text-sm text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 transition-all" />
                        </div>
                        <div className="flex justify-end gap-3 pt-2">
                            <Button variant="ghost" onClick={() => setShowAssignModal(false)}>Cancel</Button>
                            <Button onClick={handleAssignDriver} disabled={assigning}>{assigning ? 'Assigning...' : <><Send className="h-4 w-4" /> Assign & Notify</>}</Button>
                        </div>
                    </div>
                )}
            </Modal>
        </div>
    );
};

export default OperatorDashboard;
