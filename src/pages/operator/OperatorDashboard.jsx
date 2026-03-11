import { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import {
    Users, Car, MapPin, Clock, Search, Plus, Filter,
    MoreVertical, CheckCircle, XCircle, AlertCircle,
    Smartphone, QrCode, LogOut, LayoutDashboard, History,
    ChevronRight, Camera, Key, RefreshCw, Check, X,
    MessageSquare, Trash2, Phone, User, Car as CarIcon, Wrench, UserCheck, Timer, Send, CreditCard, DollarSign, Navigation, Hash, Loader2
} from 'lucide-react';
import QRCode from 'qrcode';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Select from '../../components/ui/Select';
import Modal from '../../components/ui/Modal';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import DriverSelect from '../../components/shared/DriverSelect';
import { toast } from '../../components/ui/Toast';
import { useAuth } from '../../contexts/AuthContext';
import { searchVisitorByPhone, getVisitorByPhone, createVisitor } from '../../services/visitorService';
import { findCarByNumber, createCar } from '../../services/carService';
import { createTransaction, getActiveTransactions, subscribeToTransactions, updateTransactionStatus, assignDriverForRetrieval, confirmKeyIn, getNextAvailableKeySlot } from '../../services/transactionService';
import { getDriversByCompany } from '../../services/driverService';
import { getLocationsByCompany, updateLocation } from '../../services/locationService';
import { sendCarParked, sendDriverAssigned, sendCarReady, sendCarDelivered } from '../../services/webhookService';
import { uploadMultiplePhotos } from '../../services/storageService';
import { formatTime, parseUTC } from '../../lib/utils';

// ─── Live Timer Component ───
const LiveTimer = ({ since }) => {
    const [elapsed, setElapsed] = useState('');
    useEffect(() => {
        const calc = () => {
            const parsed = parseUTC(since);
            const diff = Math.max(0, Math.floor((Date.now() - parsed.getTime()) / 1000));
            const h = Math.floor(diff / 3600);
            const m = Math.floor((diff % 3600) / 60);
            const s = diff % 60;
            setElapsed(h > 0 ? `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}` : `${m}:${s.toString().padStart(2, '0')}`);
        };
        calc();
        const id = setInterval(calc, 1000);
        return () => clearInterval(id);
    }, [since]);
    return <span className="font-mono text-xs">{elapsed}</span>;
};

// ─── Tile color config based on status ───
const tileStyles = {
    waiting_for_driver: { bg: 'bg-orange-500/10', border: 'border-orange-500/30', glow: 'shadow-orange-500/10', text: 'text-orange-400', dot: 'bg-orange-500', label: 'Waiting' },
    parked: { bg: 'bg-blue-500/5', border: 'border-blue-500/20', glow: '', text: 'text-blue-400', dot: 'bg-blue-500', label: 'Parked' },
    key_in: { bg: 'bg-indigo-500/10', border: 'border-indigo-500/30', glow: '', text: 'text-indigo-400', dot: 'bg-indigo-500', label: 'Key Secured' },
    requested: { bg: 'bg-red-500/10', border: 'border-red-500/30', glow: 'shadow-red-500/10', text: 'text-red-400', dot: 'bg-red-500', label: 'Requested' },
    driver_assigned: { bg: 'bg-amber-500/10', border: 'border-amber-500/30', glow: 'shadow-amber-500/10', text: 'text-amber-400', dot: 'bg-amber-500', label: 'Driver Assigned' },
    en_route: { bg: 'bg-yellow-500/10', border: 'border-yellow-500/30', glow: 'shadow-yellow-500/10', text: 'text-yellow-400', dot: 'bg-yellow-500', label: 'En Route' },
    arrived: { bg: 'bg-emerald-500/10', border: 'border-emerald-500/30', glow: '', text: 'text-emerald-400', dot: 'bg-emerald-500', label: 'Arrived' },
    delivered: { bg: 'bg-gray-500/5', border: 'border-gray-500/20', glow: '', text: 'text-gray-500', dot: 'bg-gray-500', label: 'Delivered' },
};

const OperatorDashboard = () => {
    const { companyId, companyName, locationId, locationName, role } = useAuth();
    const isValet = role === 'valet';

    // ─── Check-in form state ───
    const [countryCode, setCountryCode] = useState('+91');
    const [phone, setPhone] = useState('');
    const [name, setName] = useState('');
    const [carNumber, setCarNumber] = useState('');
    const [carMake, setCarMake] = useState('');
    const [parkingLocation, setParkingLocation] = useState('');
    const [selectedDriver, setSelectedDriver] = useState('');
    const [selectedLocationId, setSelectedLocationId] = useState(() => isValet ? (locationId || '') : (localStorage.getItem('vb360_last_location') || ''));
    const [loading, setLoading] = useState(false);
    const [searchResults, setSearchResults] = useState([]);
    const [showDropdown, setShowDropdown] = useState(false);
    const [existingVisitor, setExistingVisitor] = useState(null);
    const [isReturning, setIsReturning] = useState(false);
    const [keyCode, setKeyCode] = useState('');
    const [locationCapacity, setLocationCapacity] = useState(0);
    const [qrModal, setQrModal] = useState(null);          // { carNumber, name, qrDataUrl, waUrl }
    const [checkinStep, setCheckinStep] = useState(1);     // 1: Guest Info, 2: Vehicle Processing
    const [currentTxId, setCurrentTxId] = useState(null);
    const [checkinPhotos, setCheckinPhotos] = useState([]);      // preview blob URLs
    const [checkinPhotoFiles, setCheckinPhotoFiles] = useState([]); // actual File objects
    const dropdownRef = useRef(null);
    const fileInputRef = useRef(null);
    const photoInputRef = useRef(null);

    // ─── Right panel state ───
    const [transactions, setTransactions] = useState([]);
    const [drivers, setDrivers] = useState([]);
    const [locations, setLocations] = useState([]);
    const [txLoading, setTxLoading] = useState(true);
    const [isRefreshing, setIsRefreshing] = useState(false);
    const [showHistory, setShowHistory] = useState(false);

    // ─── Assignment modal ───
    const [showAssignModal, setShowAssignModal] = useState(false);
    const [selectedTx, setSelectedTx] = useState(null);
    const [assignDriverId, setAssignDriverId] = useState('');
    const [etaMinutes, setEtaMinutes] = useState(8);
    const [assigning, setAssigning] = useState(false);
    const [pickupLocation, setPickupLocation] = useState('');

    // ─── Fetch all data ───
    const activeLocationId = isValet ? locationId : selectedLocationId;
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

            if (activeLocationId) {
                const nextSlot = await getNextAvailableKeySlot(activeLocationId);
                if (nextSlot) setKeyCode(nextSlot);
                const loc = locationList.find(l => l.id === activeLocationId);
                if (loc) setLocationCapacity(loc.key_capacity || 0);
            }
        } catch (err) {
            console.error('Fetch error:', err);
        } finally {
            setTxLoading(false);
            setIsRefreshing(false);
        }
    }, [companyId, activeLocationId, isValet, locationId]);

    const handleRefresh = useCallback(() => {
        setIsRefreshing(true);
        fetchAll();
    }, [fetchAll]);

    useEffect(() => {
        fetchAll();
        const sub = subscribeToTransactions(() => fetchAll());
        const heartbeat = setInterval(() => fetchAll(), 30000);
        return () => { sub.unsubscribe(); clearInterval(heartbeat); };
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
        if (isValet && locationId) {
            setSelectedLocationId(locationId);
            handleLocationChange(locationId);
        } else if (!isValet && selectedLocationId && locations.length > 0) {
            handleLocationChange(selectedLocationId);
        }
    }, [locations.length, locationId, isValet, selectedLocationId]);

    const handleLocationChange = async (val) => {
        setSelectedLocationId(val);
        if (val) {
            if (!isValet) localStorage.setItem('vb360_last_location', val);
            try {
                const loc = locations.find(l => l.id === val);
                if (loc) setLocationCapacity(loc.key_capacity || 0);
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

    // ─── QR Code handler ───
    const handleOpenQR = async (carNum, guestName) => {
        try {
            const cleanCar = carNum.replace(/\s/g, '');
            const waMessage = encodeURIComponent(`Hi, I am ${guestName.trim()}, I have given you my car ${cleanCar}`);
            const waUrl = `https://wa.me/919106597391?text=${waMessage}`;
            const qrDataUrl = await QRCode.toDataURL(waUrl, {
                width: 256,
                margin: 2,
                color: { dark: '#000000', light: '#ffffff' }
            });
            setQrModal({ carNumber: cleanCar, name: guestName.trim(), qrDataUrl, waUrl });
        } catch (e) {
            console.error('QR generation error:', e);
            toast.error('Failed to generate QR code');
        }
    };

    // ─── Step 1: Register Guest & Generate QR ───
    const handleStep1 = async (e) => {
        e.preventDefault();
        if (!name || name.trim().length < 2) return toast.error('Guest name must be at least 2 characters');
        const cleanCar = carNumber.replace(/\s/g, '');
        if (cleanCar.length < 4) return toast.error('Car number must be at least 4 characters');
        if (!/[A-Z]/.test(cleanCar) || !/\d/.test(cleanCar)) return toast.error('Car number must contain letters and digits');

        setLoading(true);
        try {
            // Find or create visitor
            const carPhone = `CAR-${cleanCar}`;
            let visitorId;
            const existingV = await getVisitorByPhone(carPhone);
            if (existingV) {
                visitorId = existingV.id;
            } else {
                const nv = await createVisitor({ name: name.trim(), phone: carPhone });
                visitorId = nv.id;
            }

            // Find or create car
            let carId;
            const existingCar = await findCarByNumber(cleanCar);
            if (existingCar) { carId = existingCar.id; } else {
                const nc = await createCar({ car_number: cleanCar, visitor_id: visitorId, make: null, model: null });
                carId = nc.id;
            }

            // Build transaction
            const txData = {
                visitor_id: visitorId,
                car_id: carId,
                status: 'waiting_for_driver',
                valet_company_id: companyId || null,
                payment_status: 'unpaid',
            };
            if (activeLocationId) txData.location_id = activeLocationId;
            else if (selectedLocationId) txData.location_id = selectedLocationId;

            const newTx = await createTransaction(txData);
            setCurrentTxId(newTx.id);

            // Generate QR Code
            await handleOpenQR(cleanCar, name);

            // Move to Step 2
            setCheckinStep(2);
            fetchAll();
        } catch (err) {
            toast.error(err.message || 'Registration failed');
        } finally { setLoading(false); }
    };

    // ─── Step 2: Vehicle Processing (Driver, Key, Photos) ───
    const handleStep2 = async (e) => {
        if (e) e.preventDefault();
        if (!selectedDriver) return toast.error('Please select a driver');
        if (!keyCode) return toast.error('Please assign a key slot');

        setLoading(true);
        try {
            const updates = {
                parked_by_driver_id: selectedDriver,
                key_code: keyCode,
                status: 'waiting_for_driver',
            };

            // Upload check-in photos if any
            if (checkinPhotoFiles.length > 0) {
                try {
                    const urls = await uploadMultiplePhotos(checkinPhotoFiles, currentTxId, 'checkin');
                    updates.photo_urls = urls;
                } catch (uploadErr) {
                    console.error('Photo upload error:', uploadErr);
                    toast.warning('Photos could not be uploaded, continuing without them');
                }
            }

            await updateTransactionStatus(currentTxId, 'waiting_for_driver', updates);
            toast.success('Driver assigned & key slot fixed ✓');

            // Reset Flow
            setCheckinStep(1);
            setCurrentTxId(null);
            setName('');
            setCarNumber('');
            setSelectedDriver('');
            setCheckinPhotos([]);
            setCheckinPhotoFiles([]);
            fetchAll();
        } catch (err) {
            toast.error(err.message || 'Processing failed');
        } finally { setLoading(false); }
    };

    // ─── Key confirmation ───
    const handleConfirmKey = async (txId) => {
        try {
            await confirmKeyIn(txId);
            toast.success('Key secured ✓');
            fetchAll();
        } catch { toast.error('Key confirmation failed'); }
    };

    // ─── Right panel: retrieval actions ───
    const openAssignModal = (tx) => {
        setSelectedTx(tx); setAssignDriverId(tx.parked_by_driver_id || ''); setEtaMinutes(8); setPickupLocation(tx.locations?.name || ''); setShowAssignModal(true);
    };

    const handleAssignDriver = async () => {
        if (!assignDriverId) return toast.error('Select a driver');
        setAssigning(true);
        try {
            await assignDriverForRetrieval(selectedTx.id, assignDriverId, etaMinutes);
            if (pickupLocation) {
                await updateTransactionStatus(selectedTx.id, 'driver_assigned', { pickup_location: pickupLocation });
            }
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
            // Payment gating: cannot deliver without payment
            if (status === 'delivered') {
                const tx = transactions.find(t => t.id === id);
                if (tx && tx.payment_status !== 'paid') {
                    return toast.error('⛔ Payment must be confirmed before delivery');
                }
            }

            await updateTransactionStatus(id, status);
            const tx = transactions.find(t => t.id === id);

            if (status === 'arrived' && tx) {
                const loc = locations.find(l => l.id === tx.location_id);
                sendCarReady({ phone: tx.visitors?.phone, car_number: tx.cars?.car_number, location_name: loc?.name || 'N/A' });
            }
            if (status === 'delivered' && tx) {
                sendCarDelivered({ phone: tx.visitors?.phone, car_number: tx.cars?.car_number, company_name: companyName });
            }

            toast.success(status.replace(/_/g, ' '));
            fetchAll();
        } catch { toast.error('Update failed'); }
    };

    // ─── Payment toggle ───
    const handlePaymentToggle = async (tx) => {
        const newStatus = tx.payment_status === 'paid' ? 'unpaid' : 'paid';
        try {
            await updateTransactionStatus(tx.id, tx.status, { payment_status: newStatus });
            toast.success(newStatus === 'paid' ? '💰 Payment confirmed' : 'Payment unmarked');
            fetchAll();
        } catch (err) {
            console.error('Payment error:', err);
            toast.error('Payment update failed');
        }
    };

    // ─── Single-pass transaction grouping ───
    const { waitingCards, parkedCards, keyInCards, requestedCards, assignedCards, enRouteCards, arrivedCards, deliveredCars, counts } = useMemo(() => {
        const groups = { waiting_for_driver: [], parked: [], key_in: [], requested: [], driver_assigned: [], en_route: [], arrived: [], delivered: [] };
        let active = 0;
        for (const t of transactions) {
            if (groups[t.status]) groups[t.status].push(t);
            if (!['delivered', 'cancelled'].includes(t.status)) active++;
        }
        groups.delivered.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
        return {
            waitingCards: groups.waiting_for_driver, parkedCards: groups.parked, keyInCards: groups.key_in,
            requestedCards: groups.requested, assignedCards: groups.driver_assigned,
            enRouteCards: groups.en_route, arrivedCards: groups.arrived, deliveredCars: groups.delivered,
            counts: {
                active,
                requested: groups.requested.length + groups.driver_assigned.length + groups.en_route.length,
                ready: groups.arrived.length,
                delivered: groups.delivered.length,
            },
        };
    }, [transactions]);

    const driverOptions = [{ value: '', label: 'Select driver... *' }, ...drivers.map(d => ({ value: d.id, label: d.name }))];
    const locationOptions = [{ value: '', label: 'Select location...' }, ...locations.map(l => ({ value: l.id, label: l.name }))];

    // ─── Render a single car tile ───
    const renderTile = (tx) => {
        const style = tileStyles[tx.status] || tileStyles.parked;
        const isPaid = tx.payment_status === 'paid';

        return (
            <div key={tx.id} className={`rounded-xl border p-3.5 transition-all duration-300 ${style.bg} ${style.border} ${style.glow ? `shadow-lg ${style.glow}` : ''} ${tx.status === 'requested' ? 'animate-pulse-slow' : ''}`}>
                <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                            <span className={`h-2 w-2 rounded-full ${style.dot} ${tx.status === 'requested' ? 'animate-ping-slow' : ''}`} />
                            <span className="text-base font-extrabold text-white tracking-wide truncate">{tx.cars?.car_number || '—'}</span>
                            {tx.cars?.make && <span className="text-[10px] text-gray-500 hidden sm:inline">{tx.cars.make}</span>}
                        </div>
                        <p className="text-xs text-gray-400 mt-1 truncate">{tx.visitors?.name || 'Guest'} • {tx.visitors?.phone || ''}</p>
                        <div className="flex items-center gap-2 mt-1.5 flex-wrap">
                            {tx.parking_slot && <span className="text-[10px] bg-white/5 px-1.5 py-0.5 rounded text-gray-400">📍 Slot {tx.parking_slot}</span>}
                            {tx.parking_remarks && <span className="text-[10px] bg-blue-500/10 px-1.5 py-0.5 rounded text-blue-400 border border-blue-500/10" title={`Spot: ${tx.parking_remarks}`}>📍 {tx.parking_remarks}</span>}
                            {tx.parking_map_link && (
                                <a href={tx.parking_map_link} target="_blank" rel="noopener noreferrer" className="text-[10px] bg-emerald-500/10 px-1.5 py-0.5 rounded text-emerald-400 border border-emerald-500/10 hover:bg-emerald-500/20 transition-all flex items-center gap-1">
                                    🗺️ Map
                                </a>
                            )}
                            {tx.key_code && <span className="text-[10px] bg-brand-500/10 px-1.5 py-0.5 rounded text-brand-400">🔑 {tx.key_code}</span>}
                            {tx.locations?.name && <span className="text-[10px] bg-purple-500/10 px-1.5 py-0.5 rounded text-purple-400">📌 {tx.locations.name}</span>}
                            {/* QR Re-display Button */}
                            <button
                                onClick={() => handleOpenQR(tx.cars?.car_number || '', tx.visitors?.name || 'Guest')}
                                className="text-[10px] px-1.5 py-0.5 rounded bg-brand-500/10 text-brand-400 border border-brand-500/20 hover:bg-brand-500/20 transition-all flex items-center gap-1"
                                title="Show Guest QR"
                            >
                                <QrCode className="h-2.5 w-2.5" /> QR
                            </button>
                            {tx.parked_driver && <span className="text-[10px] text-blue-400">🅿 {tx.parked_driver.name}</span>}
                            {tx.retrieved_driver && <span className="text-[10px] text-amber-400">🚗 {tx.retrieved_driver.name}</span>}
                            {/* Payment Status Badge */}
                            <button
                                onClick={() => handlePaymentToggle(tx)}
                                className={`text-[10px] px-1.5 py-0.5 rounded font-medium transition-all cursor-pointer ${isPaid ? 'bg-blue-500/20 text-blue-400 border border-blue-500/30' : 'bg-gray-500/10 text-gray-500 border border-gray-500/20 hover:bg-amber-500/10 hover:text-amber-400'}`}
                                title={isPaid ? 'Click to unmark payment' : 'Click to confirm payment'}
                            >
                                {isPaid ? '💰 PAID' : '💳 UNPAID'}
                            </button>
                        </div>
                    </div>
                    <div className="flex flex-col items-end gap-1.5 shrink-0">
                        <div className={`flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-semibold uppercase tracking-wider ${style.bg} ${style.text}`}>
                            <Timer className="h-3 w-3" />
                            <LiveTimer since={tx.requested_at || tx.updated_at || tx.created_at} />
                        </div>

                        {/* Status-specific action buttons */}
                        {tx.status === 'waiting_for_driver' && (
                            tx.parked_by_driver_id ? (
                                <div className="text-[10px] px-2.5 py-1 rounded-lg bg-orange-500/5 text-orange-400 border border-orange-500/10 font-medium flex items-center gap-1.5">
                                    <Loader2 className="h-3 w-3 animate-spin" /> Driver assigned
                                </div>
                            ) : (
                                <button onClick={() => handleStatus(tx.id, 'parked')} className="text-[10px] px-2.5 py-1 rounded-lg bg-blue-500/10 text-blue-400 hover:bg-blue-500/20 border border-blue-500/20 transition-all font-medium flex items-center gap-1">
                                    <CarIcon className="h-3 w-3" /> Mark Parked
                                </button>
                            )
                        )}
                        {tx.status === 'parked' && (
                            <button onClick={() => handleConfirmKey(tx.id)} className="text-[10px] px-2.5 py-1 rounded-lg bg-indigo-500/10 text-indigo-400 hover:bg-indigo-500/20 border border-indigo-500/20 transition-all font-medium flex items-center gap-1">
                                <Key className="h-3 w-3" /> Confirm Key
                            </button>
                        )}
                        {tx.status === 'key_in' && (
                            <button onClick={() => openAssignModal(tx)} className="text-[10px] px-2.5 py-1 rounded-lg bg-blue-500/10 text-blue-400 hover:bg-blue-500/20 border border-blue-500/20 transition-all font-medium flex items-center gap-1">
                                <Send className="h-3 w-3" /> Retrieve
                            </button>
                        )}
                        {tx.status === 'requested' && (
                            <button onClick={() => openAssignModal(tx)} className="text-[10px] px-2.5 py-1 rounded-lg bg-amber-500/10 text-amber-400 hover:bg-amber-500/20 border border-amber-500/20 transition-all font-medium animate-pulse flex items-center gap-1">
                                <UserCheck className="h-3 w-3" /> Assign Driver
                            </button>
                        )}
                        {tx.status === 'driver_assigned' && (
                            <button onClick={() => handleStatus(tx.id, 'en_route')} className="text-[10px] px-2.5 py-1 rounded-lg bg-yellow-500/10 text-yellow-400 hover:bg-yellow-500/20 border border-yellow-500/20 transition-all font-medium flex items-center gap-1">
                                <Navigation className="h-3 w-3" /> En Route
                            </button>
                        )}
                        {tx.status === 'en_route' && (
                            <button onClick={() => handleStatus(tx.id, 'arrived')} className="text-[10px] px-2.5 py-1 rounded-lg bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20 border border-emerald-500/20 transition-all font-medium flex items-center gap-1">
                                <Check className="h-3 w-3" /> Arrived
                            </button>
                        )}
                        {tx.status === 'arrived' && (
                            <button
                                onClick={() => handleStatus(tx.id, 'delivered')}
                                disabled={!isPaid}
                                className={`text-[10px] px-2.5 py-1 rounded-lg border transition-all font-medium flex items-center gap-1 ${isPaid ? 'bg-gray-500/10 text-gray-300 hover:bg-gray-500/20 border-gray-500/20' : 'bg-gray-800/50 text-gray-600 border-gray-700 cursor-not-allowed opacity-50'}`}
                                title={!isPaid ? 'Payment must be confirmed first' : 'Deliver vehicle'}
                            >
                                <Check className="h-3 w-3" /> {isPaid ? 'Deliver' : '⛔ Pay First'}
                            </button>
                        )}
                    </div>
                </div>
            </div>
        );
    };

    // ─── Section renderer ───
    const renderSection = (label, cards, style) => {
        if (cards.length === 0) return null;
        return (
            <div>
                <div className="flex items-center gap-2 mb-2">
                    <span className={`h-2 w-2 rounded-full ${style.dot} ${label === 'Requested' ? 'animate-ping-slow' : ''}`} />
                    <h3 className={`text-xs font-bold uppercase tracking-wider ${style.text}`}>
                        {label} ({cards.length})
                    </h3>
                </div>
                <div className="space-y-2">{cards.map(renderTile)}</div>
            </div>
        );
    };

    return (
        <div className="animate-fade-in">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">

                {/* ═══ LEFT: Check-In Form ═══ */}
                <div className="flex flex-col h-full">
                    <div className="mb-6">
                        <div className="flex items-center justify-between mb-2">
                            <h1 className="text-xl font-bold text-white tracking-tight">Entry Process</h1>
                            <span className="text-[10px] font-bold text-brand-400 bg-brand-500/10 px-2 py-1 rounded-full uppercase tracking-widest">
                                Step {checkinStep} of 2
                            </span>
                        </div>
                        {/* Progress Bar */}
                        <div className="h-1 bg-dark-600 rounded-full overflow-hidden">
                            <div className={`h-full rounded-full transition-all duration-500 ${checkinStep === 1 ? 'w-1/2 bg-brand-500' : 'w-full bg-emerald-500'}`} />
                        </div>
                    </div>

                    <Card className="p-5 relative overflow-hidden flex-1">
                        <div className="absolute top-0 left-0 w-full h-px bg-gradient-to-r from-transparent via-brand-500/30 to-transparent" />

                        {checkinStep === 1 ? (
                            <form onSubmit={handleStep1} className="space-y-4">
                                {/* Location */}
                                {locations.length > 0 && (
                                    isValet && locationId ? (
                                        <div className="bg-brand-500/5 border border-brand-500/20 rounded-xl p-3 flex items-center gap-3">
                                            <div className="bg-brand-500/10 p-2 rounded-lg"><MapPin className="h-4 w-4 text-brand-400" /></div>
                                            <div>
                                                <p className="text-[10px] text-gray-500 uppercase tracking-wider font-semibold">Assigned Post</p>
                                                <p className="text-sm font-bold text-white uppercase">{locationName || 'Assigned Location'}</p>
                                            </div>
                                        </div>
                                    ) : (
                                        <Select label={<span className="flex items-center gap-2 text-xs"><MapPin className="h-3.5 w-3.5 text-brand-500" /> Service Location</span>}
                                            options={locationOptions} value={selectedLocationId} onChange={(e) => handleLocationChange(e.target.value)} />
                                    )
                                )}

                                {/* Car Number (FIRST — central key) */}
                                <div className="space-y-1">
                                    <label className="flex items-center gap-2 text-xs font-medium text-gray-300">
                                        <CarIcon className="h-3.5 w-3.5 text-brand-500" /> Car Number <span className="text-red-400">*</span>
                                        {isReturning && <span className="text-[10px] text-emerald-400 ml-auto">✓ Returning</span>}
                                    </label>
                                    <div className="relative group">
                                        <CarIcon className="absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-gray-500" />
                                        <input type="text" value={carNumber} onChange={(e) => {
                                            const val = e.target.value.toUpperCase().replace(/\s/g, '');
                                            setCarNumber(val);
                                            setIsReturning(false);
                                            if (val.length >= 4) {
                                                clearTimeout(window._carLookupTimer);
                                                window._carLookupTimer = setTimeout(async () => {
                                                    try {
                                                        const car = await findCarByNumber(val);
                                                        if (car?.visitors?.name) {
                                                            const latestName = car.visitors.name.split(';').pop().trim();
                                                            setName(latestName);
                                                            setIsReturning(true);
                                                        }
                                                    } catch { /* not found */ }
                                                }, 400);
                                            }
                                        }} placeholder="MH01AB1234" required className="block w-full rounded-xl border-0 bg-dark-600 py-2.5 pl-9 pr-3 text-sm text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 transition-all uppercase tracking-wider font-semibold" />
                                    </div>
                                </div>

                                {/* Guest Name (auto-filled for returning vehicles) */}
                                <div className="space-y-1">
                                    <label className="flex items-center gap-2 text-xs font-medium text-gray-300"><User className="h-3.5 w-3.5 text-brand-500" /> Guest Name <span className="text-red-400">*</span></label>
                                    <div className="relative group">
                                        <User className="absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-gray-500" />
                                        <input type="text" value={name} onChange={(e) => setName(e.target.value)} placeholder="Guest name" required className="block w-full rounded-xl border-0 bg-dark-600 py-2.5 pl-9 pr-3 text-sm text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 transition-all" />
                                    </div>
                                </div>

                                <Button type="submit" size="lg" className="w-full" disabled={loading}>
                                    {loading ? <span className="flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Registering...</span>
                                        : <span className="flex items-center gap-2"><QrCode className="h-4 w-4" /> Register & Show QR</span>}
                                </Button>
                            </form>
                        ) : (
                            <form onSubmit={handleStep2} className="space-y-4 relative">
                                {/* QR Re-display button for Step 2 */}
                                <div className="absolute top-0 right-0 p-1">
                                    <button
                                        type="button"
                                        onClick={() => handleOpenQR(carNumber, name)}
                                        className="p-2 rounded-lg bg-brand-500/10 text-brand-400 hover:bg-brand-500/20 transition-all border border-brand-500/10 shadow-lg"
                                        title="Show QR Code again"
                                    >
                                        <QrCode className="h-4 w-4" />
                                    </button>
                                </div>

                                <div className="bg-emerald-500/5 border border-emerald-500/20 rounded-xl p-3">
                                    <p className="text-xs text-emerald-400 font-semibold">✓ Guest registered — Now assign driver & key</p>
                                    <p className="text-sm font-bold text-white mt-1">{carNumber} • {name}</p>
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
                                </div>

                                {/* Driver Select */}
                                <DriverSelect
                                    companyId={companyId}
                                    value={selectedDriver}
                                    onChange={(e) => setSelectedDriver(e.target.value)}
                                    required
                                />
                                {/* ─── Check-in Photos ─── */}
                                <div className="space-y-2">
                                    <label className="flex items-center gap-2 text-xs font-medium text-gray-300">
                                        <Camera className="h-3.5 w-3.5 text-brand-500" /> Vehicle Photos
                                        {checkinPhotos.length > 0 && <span className="text-[10px] text-gray-500 ml-auto">{checkinPhotos.length} photo{checkinPhotos.length > 1 ? 's' : ''}</span>}
                                    </label>
                                    {/* Thumbnails */}
                                    {checkinPhotos.length > 0 && (
                                        <div className="flex flex-wrap gap-2">
                                            {checkinPhotos.map((url, i) => (
                                                <div key={i} className="relative group">
                                                    <img src={url} alt={`Photo ${i + 1}`} className="h-16 w-16 rounded-lg object-cover border border-white/10" />
                                                    <button type="button" onClick={() => {
                                                        setCheckinPhotos(p => p.filter((_, idx) => idx !== i));
                                                        setCheckinPhotoFiles(p => p.filter((_, idx) => idx !== i));
                                                    }} className="absolute -top-1.5 -right-1.5 h-5 w-5 bg-red-500 text-white rounded-full text-[10px] flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity shadow-lg">✕</button>
                                                </div>
                                            ))}
                                        </div>
                                    )}
                                    {/* Camera + Gallery buttons */}
                                    <div className="flex gap-2">
                                        <button type="button" onClick={() => photoInputRef.current?.click()}
                                            className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl bg-brand-500/10 hover:bg-brand-500/20 text-brand-400 text-xs font-semibold border border-brand-500/20 transition-all">
                                            <Camera className="h-4 w-4" /> Take Photo
                                        </button>
                                        <button type="button" onClick={() => {
                                            const inp = document.createElement('input');
                                            inp.type = 'file'; inp.accept = 'image/*'; inp.multiple = true;
                                            inp.onchange = (ev) => {
                                                const files = Array.from(ev.target.files || []);
                                                setCheckinPhotoFiles(prev => [...prev, ...files]);
                                                setCheckinPhotos(prev => [...prev, ...files.map(f => URL.createObjectURL(f))]);
                                            };
                                            inp.click();
                                        }}
                                            className="flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-dark-600 hover:bg-dark-500 text-gray-400 text-xs font-medium border border-white/5 transition-all">
                                            📁 Gallery
                                        </button>
                                    </div>
                                    {/* Hidden camera input */}
                                    <input ref={photoInputRef} type="file" accept="image/*" capture="environment" className="hidden"
                                        onChange={(e) => {
                                            const files = Array.from(e.target.files || []);
                                            setCheckinPhotoFiles(prev => [...prev, ...files]);
                                            setCheckinPhotos(prev => [...prev, ...files.map(f => URL.createObjectURL(f))]);
                                            e.target.value = '';
                                        }} />
                                </div>

                                <Button type="submit" size="lg" className="w-full" disabled={loading}>
                                    {loading ? <span className="flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Processing...</span>
                                        : <span className="flex items-center gap-2"><Check className="h-4 w-4" /> Assign & Complete</span>}
                                </Button>
                            </form>
                        )}
                    </Card>
                </div>

                {/* ═══ RIGHT: Car Retrieval Panel ═══ */}
                <div>
                    <div className="flex items-center justify-between mb-5">
                        <div>
                            <h1 className="text-xl font-bold text-white">Cars</h1>
                            <p className="text-xs text-gray-500 mt-0.5">
                                {counts.active} active • {counts.requested} requested • {counts.ready} ready
                            </p>
                        </div>
                        <button onClick={handleRefresh} disabled={isRefreshing} className="p-2 rounded-xl hover:bg-white/5 text-gray-400 hover:text-white transition-colors disabled:opacity-50">
                            <RefreshCw className={`h-4 w-4 ${isRefreshing ? 'animate-spin' : ''}`} />
                        </button>
                    </div>

                    {/* ─── SECTIONED TILES ─── */}
                    {txLoading ? (
                        <Card className="p-8 text-center">
                            <LoadingSpinner size="md" className="mx-auto" />
                        </Card>
                    ) : (counts.active === 0 && deliveredCars.length === 0) ? (
                        <Card className="p-8 text-center"><CarIcon className="h-8 w-8 text-gray-600 mx-auto mb-2" /><p className="text-gray-500 text-sm">No active cars</p></Card>
                    ) : (
                        <div className="space-y-4 max-h-[calc(100vh-320px)] overflow-y-auto pr-1 scrollbar-thin">
                            {renderSection('Waiting', waitingCards, tileStyles.waiting_for_driver)}
                            {renderSection('Parked', parkedCards, tileStyles.parked)}
                            {renderSection('Key Secured', keyInCards, tileStyles.key_in)}
                            {renderSection('Requested', requestedCards, tileStyles.requested)}
                            {renderSection('Driver Assigned', assignedCards, tileStyles.driver_assigned)}
                            {renderSection('En Route', enRouteCards, tileStyles.en_route)}
                            {renderSection('Arrived', arrivedCards, tileStyles.arrived)}
                        </div>
                    )}

                    {/* Delivered history toggle */}
                    {deliveredCars.length > 0 && (
                        <div className="mt-4">
                            <button onClick={() => setShowHistory(!showHistory)} className="text-xs text-gray-400 hover:text-white transition-all flex items-center gap-2">
                                <History className="h-3.5 w-3.5" /> {showHistory ? 'Hide' : 'Show'} Delivered ({deliveredCars.length})
                            </button>
                            {showHistory && (
                                <div className="space-y-2 mt-2 max-h-80 overflow-y-auto pr-1">
                                    {deliveredCars.map(renderTile)}
                                </div>
                            )}
                        </div>
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

            {/* ═══ QR Code Modal ═══ */}
            {qrModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-[#111111] backdrop-blur-sm" onClick={() => setQrModal(null)}>
                    {/* Floating Logo Circle */}
                    <div className="absolute top-[calc(50%-220px)] left-1/2 -translate-x-1/2 z-10 w-[60px] h-[60px] rounded-full bg-[#1e1e2d] border-[3px] border-[#111111] flex items-center justify-center overflow-hidden shadow-lg">
                        <span className="text-xl font-bold bg-gradient-to-r from-pink-500 to-purple-500 bg-clip-text text-transparent italic pr-1">
                            {companyName?.charAt(0) || 'V'}
                        </span>
                    </div>

                    {/* Main White Card */}
                    <div className="bg-white rounded-[20px] pt-12 pb-8 px-8 max-w-[320px] w-full mx-4 text-center relative mt-4" onClick={e => e.stopPropagation()} id="qr-receipt">
                        <h2 className="text-[22px] font-bold text-gray-900 mb-0.5 tracking-tight">{companyName || 'Valet Pro'}</h2>
                        <p className="text-[13px] text-gray-500 mb-6 font-medium">WhatsApp business account</p>

                        <div className="bg-white p-2 rounded-xl border border-gray-100 shadow-sm mx-auto w-fit mb-6">
                            <img
                                src={qrModal.qrDataUrl}
                                alt="WhatsApp QR"
                                className="w-[200px] h-[200px] object-cover rounded-lg"
                            />
                        </div>

                        {/* Guest Info */}
                        <div className="flex justify-center gap-3 text-xs text-gray-500 font-medium mb-6">
                            <span className="bg-gray-100 px-3 py-1.5 rounded-lg">{qrModal.carNumber}</span>
                            <span className="bg-gray-100 px-3 py-1.5 rounded-lg truncate max-w-[120px]">{qrModal.name}</span>
                        </div>

                        {/* Next Button */}
                        <button
                            onClick={() => setQrModal(null)}
                            className="w-full bg-gray-900 text-white py-3.5 rounded-xl font-bold text-sm transition-all active:scale-[0.98] shadow-lg shadow-black/20 flex items-center justify-center gap-2"
                        >
                            Next <ChevronRight className="h-4 w-4" />
                        </button>
                    </div>

                    {/* Bottom Text */}
                    <div className="absolute bottom-12 w-full text-center px-6">
                        <p className="text-[#8e8e93] text-[15px] max-w-[280px] mx-auto leading-snug">
                            Scan this code to start a WhatsApp<br />chat with {companyName || 'Valet Pro'}.
                        </p>
                    </div>

                    {/* Print Button */}
                    <button onClick={() => window.print()} className="absolute top-4 right-4 text-white/20 hover:text-white/80 p-2">
                        🖨️
                    </button>
                    <button onClick={() => setQrModal(null)} className="absolute top-4 left-4 text-white/20 hover:text-white/80 p-2 text-2xl leading-none">
                        ×
                    </button>
                </div>
            )}
        </div>
    );
};

export default OperatorDashboard;
