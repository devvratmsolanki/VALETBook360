import { useState, useEffect, useCallback, useMemo } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { updateTransactionStatus } from '../../services/transactionService';
import { uploadMultiplePhotos } from '../../services/storageService';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import { toast } from '../../components/ui/Toast';
import { Car, MapPin, Key, Clock, Navigation, Check, ArrowRight, Loader2, User, Phone, RefreshCw, Camera, MessageSquare } from 'lucide-react';

// ─── Live Timer ───
const LiveTimer = ({ since }) => {
    const [elapsed, setElapsed] = useState('');
    useEffect(() => {
        const calc = () => {
            const diff = Date.now() - new Date(since).getTime();
            const h = Math.floor(diff / 3600000);
            const m = Math.floor((diff % 3600000) / 60000);
            setElapsed(h > 0 ? `${h}h ${m}m` : `${m}m`);
        };
        calc();
        const iv = setInterval(calc, 30000);
        return () => clearInterval(iv);
    }, [since]);
    return <span>{elapsed}</span>;
};

// ─── Status badge ───
const statusColors = {
    waiting_for_driver: { bg: 'bg-orange-500/10', text: 'text-orange-400', border: 'border-orange-500/20', label: '🟠 Waiting' },
    parked: { bg: 'bg-brand-500/10', text: 'text-brand-400', border: 'border-brand-500/20', label: '🅿️ Parked' },
    driver_assigned: { bg: 'bg-purple-500/10', text: 'text-purple-400', border: 'border-purple-500/20', label: '🔔 Assigned' },
    en_route: { bg: 'bg-blue-500/10', text: 'text-blue-400', border: 'border-blue-500/20', label: '🚗 En Route' },
    arrived: { bg: 'bg-emerald-500/10', text: 'text-emerald-400', border: 'border-emerald-500/20', label: '✅ Arrived' },
};

const DriverPanel = () => {
    const { user, profile, companyId } = useAuth();
    const [activeTab, setActiveTab] = useState('park');
    const [transactions, setTransactions] = useState([]);
    const [driverId, setDriverId] = useState(null);
    const [driverName, setDriverName] = useState('');
    const [loading, setLoading] = useState(true);
    const [actionLoading, setActionLoading] = useState(null);
    const [gpsLoading, setGpsLoading] = useState(null);
    const [showPermissionModal, setShowPermissionModal] = useState(false);
    const [parkingRemarks, setParkingRemarks] = useState({});  // { txId: 'remark' }
    const [parkingPhotos, setParkingPhotos] = useState({});    // { txId: [preview urls] }
    const [parkingPhotoFiles, setParkingPhotoFiles] = useState({}); // { txId: [File objects] }

    // Find the driver record for the logged-in user
    useEffect(() => {
        const findDriver = async () => {
            if (!user || !profile) return;

            let query = supabase.from('drivers').select('id, name, staff_id');
            if (companyId) {
                query = query.eq('valet_company_id', companyId);
            }

            const { data: drivers } = await query;
            if (!drivers || drivers.length === 0) return;

            const driver = drivers[0];
            setDriverId(driver.id);
            setDriverName(driver.name || 'Driver');
        };
        findDriver();
    }, [user, profile, companyId]);

    // Fetch transactions assigned to this driver
    const fetchTransactions = useCallback(async () => {
        if (!driverId) return;
        try {
            const { data, error } = await supabase
                .from('valet_transactions')
                .select(`
                    *,
                    visitors(id, name, phone),
                    cars(id, car_number, make, model, color),
                    locations:location_id(id, name)
                `)
                .or(`parked_by_driver_id.eq.${driverId},retrieved_by_driver_id.eq.${driverId}`)
                .in('status', ['waiting_for_driver', 'parked', 'key_in', 'requested', 'driver_assigned', 'en_route', 'arrived'])
                .order('created_at', { ascending: false });
            if (error) throw error;
            setTransactions(data || []);
        } catch (err) {
            console.error('Error fetching driver transactions:', err);
            toast.error('Failed to load tasks');
        } finally {
            setLoading(false);
        }
    }, [driverId]);

    useEffect(() => {
        fetchTransactions();
    }, [fetchTransactions]);

    // Real-time subscription
    useEffect(() => {
        if (!driverId) return;
        const sub = supabase
            .channel('driver-tasks')
            .on('postgres_changes', {
                event: '*',
                schema: 'public',
                table: 'valet_transactions',
            }, () => {
                fetchTransactions();
            })
            .subscribe();
        return () => sub.unsubscribe();
    }, [driverId, fetchTransactions]);

    // ─── GPS Capture + Mark Parked ───
    const handleMarkParked = async (txId) => {
        setGpsLoading(txId);
        try {
            // Capture GPS coordinates
            let coordinates = null;
            let mapLink = null;
            try {
                const pos = await new Promise((resolve, reject) => {
                    navigator.geolocation.getCurrentPosition(resolve, reject, {
                        enableHighAccuracy: true,
                        timeout: 8000,
                        maximumAge: 0,
                    });
                });
                const lat = pos.coords.latitude.toFixed(6);
                const lng = pos.coords.longitude.toFixed(6);
                coordinates = `${lat},${lng}`;
                mapLink = `https://maps.google.com/?q=${lat},${lng}`;
            } catch (err) {
                console.error('GPS Error:', err);
                if (err.code === 1) {
                    setShowPermissionModal(true);
                } else if (err.code === 2 || err.code === 3) {
                    // Try again with lower accuracy if high accuracy timed out or failed
                    try {
                        const pos = await new Promise((resolve, reject) => {
                            navigator.geolocation.getCurrentPosition(resolve, reject, {
                                enableHighAccuracy: false,
                                timeout: 10000,
                                maximumAge: 60000,
                            });
                        });
                        const lat = pos.coords.latitude.toFixed(6);
                        const lng = pos.coords.longitude.toFixed(6);
                        coordinates = `${lat},${lng}`;
                        mapLink = `https://maps.google.com/?q=${lat},${lng}`;
                    } catch {
                        toast.warning('GPS signal weak — parking without coordinates');
                    }
                } else {
                    toast.warning('GPS not available — parking without coordinates');
                }
            }

            // Update transaction with GPS, remarks, and photos
            const extraFields = {};
            if (coordinates) extraFields.parking_coordinates = coordinates;
            if (mapLink) extraFields.parking_map_link = mapLink;
            if (parkingRemarks[txId]) extraFields.parking_remarks = parkingRemarks[txId];

            // Upload parking photos to Supabase Storage
            if (parkingPhotoFiles[txId]?.length > 0) {
                try {
                    const uploadedUrls = await uploadMultiplePhotos(parkingPhotoFiles[txId], txId, 'parking');
                    extraFields.parking_photos = uploadedUrls;
                } catch (uploadErr) {
                    console.error('Photo upload error:', uploadErr);
                    toast.warning('Photos could not be uploaded, continuing without them');
                }
            }

            await updateTransactionStatus(txId, 'parked', extraFields);
            toast.success('✅ Car marked as parked!' + (mapLink ? ' GPS captured.' : ''));
            // Clear local state for this tx
            setParkingRemarks(prev => { const n = { ...prev }; delete n[txId]; return n; });
            setParkingPhotos(prev => { const n = { ...prev }; delete n[txId]; return n; });
            setParkingPhotoFiles(prev => { const n = { ...prev }; delete n[txId]; return n; });
            fetchTransactions();
        } catch (err) {
            console.error('Mark parked error:', err);
            toast.error('Failed to mark as parked');
        } finally {
            setGpsLoading(null);
        }
    };

    // ─── Status transition handlers ───
    const handleStatusChange = async (txId, newStatus, label) => {
        setActionLoading(txId);
        try {
            await updateTransactionStatus(txId, newStatus);
            toast.success(`${label} updated!`);
            fetchTransactions();
        } catch {
            toast.error(`Failed to update: ${label}`);
        } finally {
            setActionLoading(null);
        }
    };

    // ─── Single-pass transaction grouping ───
    const { parkQueue, retrieveQueue, recentlyParked } = useMemo(() => {
        const park = [], retrieve = [], parked = [];
        for (const t of transactions) {
            if (t.parked_by_driver_id === driverId && t.status === 'waiting_for_driver') park.push(t);
            else if (t.retrieved_by_driver_id === driverId && (t.status === 'driver_assigned' || t.status === 'en_route' || t.status === 'arrived')) retrieve.push(t);
            else if (t.parked_by_driver_id === driverId && (t.status === 'parked' || t.status === 'key_in')) parked.push(t);
        }
        return { parkQueue: park, retrieveQueue: retrieve, recentlyParked: parked };
    }, [transactions, driverId]);

    // ─── Render a park task card ───
    const renderParkCard = (tx) => (
        <div key={tx.id} className="bg-dark-800/80 rounded-2xl border border-white/5 overflow-hidden mb-3">
            <div className="bg-gradient-to-r from-orange-500/10 to-transparent p-4">
                <div className="flex items-center justify-between">
                    <div>
                        <p className="text-lg font-bold text-white tracking-wider">🚗 {tx.cars?.car_number || 'N/A'}</p>
                        {tx.cars?.make && <p className="text-xs text-gray-500">{tx.cars.make} {tx.cars.model}</p>}
                    </div>
                    <div className={`px-2.5 py-1 rounded-full text-[10px] font-semibold uppercase ${statusColors.waiting_for_driver.bg} ${statusColors.waiting_for_driver.text} border ${statusColors.waiting_for_driver.border}`}>
                        Waiting
                    </div>
                </div>
            </div>
            <div className="px-4 pb-4 space-y-2">
                <div className="grid grid-cols-2 gap-2">
                    {tx.visitors?.name && (
                        <div className="flex items-center gap-2 bg-dark-700/50 rounded-lg px-3 py-2">
                            <User className="h-3.5 w-3.5 text-brand-400" />
                            <span className="text-xs text-gray-300">{tx.visitors.name}</span>
                        </div>
                    )}
                    {tx.key_code && (
                        <div className="flex items-center gap-2 bg-amber-500/10 rounded-lg px-3 py-2 border border-amber-500/10">
                            <Key className="h-3.5 w-3.5 text-amber-400" />
                            <span className="text-xs text-amber-300 font-semibold">Slot {tx.key_code}</span>
                        </div>
                    )}
                    {tx.parking_slot && (
                        <div className="flex items-center gap-2 bg-dark-700/50 rounded-lg px-3 py-2">
                            <MapPin className="h-3.5 w-3.5 text-brand-400" />
                            <span className="text-xs text-gray-300">Slot {tx.parking_slot}</span>
                        </div>
                    )}
                    <div className="flex items-center gap-2 bg-dark-700/50 rounded-lg px-3 py-2">
                        <Clock className="h-3.5 w-3.5 text-brand-400" />
                        <span className="text-xs text-gray-300"><LiveTimer since={tx.created_at} /> ago</span>
                    </div>
                </div>

                {/* Parking Remarks */}
                <div className="space-y-1">
                    <label className="flex items-center gap-1.5 text-[10px] font-medium text-gray-500 uppercase tracking-wider">
                        <MapPin className="h-3 w-3" /> Parking Location Remarks
                        <span className="ml-auto normal-case text-gray-600">(Optional - e.g. Pillar B2)</span>
                    </label>
                    <input
                        type="text"
                        value={parkingRemarks[tx.id] || ''}
                        onChange={(e) => setParkingRemarks(prev => ({ ...prev, [tx.id]: e.target.value }))}
                        placeholder="e.g. Near Pillar B2, Zone A"
                        className="w-full rounded-lg border-0 bg-dark-700/50 py-2.5 px-3 text-sm text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 transition-all placeholder:text-gray-600"
                    />
                </div>

                {/* GPS Status Indicator */}
                <div className="flex items-center justify-between px-1">
                    <div className="flex items-center gap-2">
                        <div className={`h-2 w-2 rounded-full animate-pulse ${gpsLoading === tx.id ? 'bg-amber-500' : 'bg-emerald-500'}`} />
                        <span className="text-[10px] text-gray-400 font-medium uppercase tracking-tight">
                            {gpsLoading === tx.id ? 'Accessing GPS...' : 'GPS Ready for capture'}
                        </span>
                    </div>
                </div>

                {/* Parking Photos */}
                <div className="space-y-1.5">
                    <label className="flex items-center gap-1.5 text-[10px] font-medium text-gray-500 uppercase tracking-wider">
                        <Camera className="h-3 w-3" /> Parking Spot Photos
                        {parkingPhotos[tx.id]?.length > 0 && <span className="ml-auto normal-case text-gray-600">{parkingPhotos[tx.id].length} photo{parkingPhotos[tx.id].length > 1 ? 's' : ''}</span>}
                    </label>
                    {/* Thumbnails */}
                    {parkingPhotos[tx.id]?.length > 0 && (
                        <div className="flex flex-wrap gap-2">
                            {parkingPhotos[tx.id].map((url, i) => (
                                <div key={i} className="relative group">
                                    <img src={url} alt={`Photo ${i + 1}`} className="h-14 w-14 rounded-lg object-cover border border-white/10" />
                                    <button type="button" onClick={() => {
                                        setParkingPhotos(prev => ({ ...prev, [tx.id]: prev[tx.id].filter((_, idx) => idx !== i) }));
                                        setParkingPhotoFiles(prev => ({ ...prev, [tx.id]: prev[tx.id].filter((_, idx) => idx !== i) }));
                                    }} className="absolute -top-1 -right-1 h-4 w-4 bg-red-500 text-white rounded-full text-[9px] flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity shadow">✕</button>
                                </div>
                            ))}
                        </div>
                    )}
                    {/* Camera + Gallery buttons */}
                    <div className="flex gap-2">
                        <button type="button" onClick={() => document.getElementById(`cam-${tx.id}`).click()}
                            className="flex-1 flex items-center justify-center gap-2 py-2 rounded-xl bg-brand-500/10 hover:bg-brand-500/20 text-brand-400 text-xs font-semibold border border-brand-500/20 transition-all">
                            <Camera className="h-3.5 w-3.5" /> Take Photo
                        </button>
                        <button type="button" onClick={() => {
                            const inp = document.createElement('input');
                            inp.type = 'file'; inp.accept = 'image/*'; inp.multiple = true;
                            inp.onchange = (ev) => {
                                const files = Array.from(ev.target.files || []);
                                setParkingPhotos(prev => ({ ...prev, [tx.id]: [...(prev[tx.id] || []), ...files.map(f => URL.createObjectURL(f))] }));
                                setParkingPhotoFiles(prev => ({ ...prev, [tx.id]: [...(prev[tx.id] || []), ...files] }));
                            };
                            inp.click();
                        }}
                            className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-dark-700/50 hover:bg-dark-600 text-gray-400 text-xs font-medium border border-white/5 transition-all">
                            📁 Gallery
                        </button>
                    </div>
                    <input id={`cam-${tx.id}`} type="file" accept="image/*" capture="environment" className="hidden"
                        onChange={(e) => {
                            const files = Array.from(e.target.files || []);
                            setParkingPhotos(prev => ({ ...prev, [tx.id]: [...(prev[tx.id] || []), ...files.map(f => URL.createObjectURL(f))] }));
                            setParkingPhotoFiles(prev => ({ ...prev, [tx.id]: [...(prev[tx.id] || []), ...files] }));
                            e.target.value = '';
                        }} />
                </div>

                {/* Mark Parked Button */}
                <button
                    onClick={() => handleMarkParked(tx.id)}
                    disabled={gpsLoading === tx.id}
                    className="w-full bg-gradient-to-r from-emerald-500 to-emerald-600 hover:from-emerald-600 hover:to-emerald-700 text-white py-3.5 rounded-xl font-semibold text-sm transition-all active:scale-[0.98] disabled:opacity-50 flex items-center justify-center gap-2 mt-2"
                >
                    {gpsLoading === tx.id ? (
                        <><Loader2 className="h-4 w-4 animate-spin" /> Capturing GPS...</>
                    ) : (
                        <><Navigation className="h-4 w-4" /> Mark as Parked 📍</>
                    )}
                </button>
            </div>
        </div>
    );

    // ─── Render recently parked (showing key code) ───
    const renderParkedCard = (tx) => (
        <div key={tx.id} className="bg-dark-800/80 rounded-2xl border border-brand-500/10 overflow-hidden mb-3">
            <div className="bg-gradient-to-r from-brand-500/10 to-transparent p-4">
                <div className="flex items-center justify-between">
                    <p className="text-lg font-bold text-white">🅿️ {tx.cars?.car_number || 'N/A'}</p>
                    <div className="px-2.5 py-1 rounded-full text-[10px] font-semibold uppercase bg-brand-500/10 text-brand-400 border border-brand-500/20">Parked</div>
                </div>
            </div>
            <div className="px-4 pb-4 space-y-3">
                <div className="flex items-center gap-3 p-3 bg-amber-500/5 border border-amber-500/10 rounded-xl">
                    <Key className="h-5 w-5 text-amber-400 shrink-0" />
                    <div className="flex-1">
                        <p className="text-sm font-bold text-amber-300">Key Slot: {tx.key_code || 'N/A'}</p>
                        <p className="text-[10px] text-amber-400/60 uppercase tracking-wider font-semibold">Hand over key to operator</p>
                    </div>
                </div>

                {(tx.parking_remarks || tx.parking_map_link) && (
                    <div className="space-y-2 p-3 bg-dark-700/30 rounded-xl border border-white/5">
                        {tx.parking_remarks && (
                            <div className="flex items-start gap-2">
                                <MapPin className="h-3.5 w-3.5 text-brand-400 mt-0.5" />
                                <div>
                                    <p className="text-[10px] text-gray-500 uppercase font-bold tracking-tight">Parking Spot</p>
                                    <p className="text-sm font-semibold text-gray-200">{tx.parking_remarks}</p>
                                </div>
                            </div>
                        )}
                        {tx.parking_map_link && (
                            <a href={tx.parking_map_link} target="_blank" rel="noopener noreferrer"
                                className="flex items-center justify-center gap-2 py-2 w-full bg-blue-500/10 hover:bg-blue-500/20 rounded-lg text-xs text-blue-400 font-bold transition-all border border-blue-500/20">
                                <Navigation className="h-3 w-3" /> Open in Google Maps
                            </a>
                        )}
                    </div>
                )}
            </div>
        </div>
    );

    // ─── Render a retrieval task card ───
    const renderRetrieveCard = (tx) => {
        const style = statusColors[tx.status] || statusColors.driver_assigned;
        return (
            <div key={tx.id} className="bg-dark-800/80 rounded-2xl border border-white/5 overflow-hidden mb-3">
                <div className="bg-gradient-to-r from-purple-500/10 to-transparent p-4">
                    <div className="flex items-center justify-between">
                        <div>
                            <p className="text-lg font-bold text-white">🚗 {tx.cars?.car_number || 'N/A'}</p>
                            {tx.cars?.make && <p className="text-xs text-gray-500">{tx.cars.make} {tx.cars.model}</p>}
                        </div>
                        <div className={`px-2.5 py-1 rounded-full text-[10px] font-semibold uppercase ${style.bg} ${style.text} border ${style.border}`}>
                            {style.label}
                        </div>
                    </div>
                </div>
                <div className="px-4 pb-4 space-y-2">
                    <div className="grid grid-cols-2 gap-2">
                        {tx.key_code && (
                            <div className="flex items-center gap-2 bg-amber-500/10 rounded-lg px-3 py-2 border border-amber-500/10">
                                <Key className="h-3.5 w-3.5 text-amber-400" />
                                <span className="text-xs text-amber-300 font-semibold">Key: {tx.key_code}</span>
                            </div>
                        )}
                        {tx.pickup_location && (
                            <div className="flex items-center gap-2 bg-dark-700/50 rounded-lg px-3 py-2">
                                <MapPin className="h-3.5 w-3.5 text-brand-400" />
                                <span className="text-xs text-gray-300 truncate">{tx.pickup_location}</span>
                            </div>
                        )}
                        {tx.eta_minutes && (
                            <div className="flex items-center gap-2 bg-dark-700/50 rounded-lg px-3 py-2">
                                <Clock className="h-3.5 w-3.5 text-brand-400" />
                                <span className="text-xs text-gray-300">ETA: {tx.eta_minutes} min</span>
                            </div>
                        )}
                        {tx.visitors?.phone && (
                            <a href={`tel:${tx.visitors.phone}`} className="flex items-center gap-2 bg-dark-700/50 rounded-lg px-3 py-2 hover:bg-dark-600/50">
                                <Phone className="h-3.5 w-3.5 text-brand-400" />
                                <span className="text-xs text-gray-300">{tx.visitors.phone}</span>
                            </a>
                        )}
                    </div>

                    {/* Parking location map */}
                    {(tx.parking_remarks || tx.parking_map_link) && (
                        <div className="space-y-2 p-3 bg-blue-500/5 border border-blue-500/10 rounded-xl">
                            {tx.parking_remarks && (
                                <div className="flex items-start gap-2">
                                    <MapPin className="h-4 w-4 text-blue-400 mt-0.5" />
                                    <div>
                                        <p className="text-[10px] text-blue-500/60 uppercase font-bold tracking-tight">Parking Spot</p>
                                        <p className="text-sm font-bold text-blue-300">{tx.parking_remarks}</p>
                                    </div>
                                </div>
                            )}
                            {tx.parking_map_link && (
                                <a href={tx.parking_map_link} target="_blank" rel="noopener noreferrer"
                                    className="flex items-center justify-center gap-2 py-2.5 w-full bg-blue-500/20 hover:bg-blue-500/30 rounded-lg text-xs text-blue-300 font-bold transition-all border border-blue-500/30">
                                    <Navigation className="h-3.5 w-3.5" /> Navigate to parked car →
                                </a>
                            )}
                        </div>
                    )}

                    {/* Status action buttons */}
                    <div className="flex gap-2 mt-2">
                        {tx.status === 'driver_assigned' && (
                            <button
                                onClick={() => handleStatusChange(tx.id, 'en_route', 'En Route')}
                                disabled={actionLoading === tx.id}
                                className="flex-1 bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-600 hover:to-blue-700 text-white py-3 rounded-xl font-semibold text-sm transition-all active:scale-[0.98] disabled:opacity-50 flex items-center justify-center gap-2"
                            >
                                {actionLoading === tx.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <ArrowRight className="h-4 w-4" />}
                                I'm On My Way
                            </button>
                        )}
                        {tx.status === 'en_route' && (
                            <button
                                onClick={() => handleStatusChange(tx.id, 'arrived', 'Arrived')}
                                disabled={actionLoading === tx.id}
                                className="flex-1 bg-gradient-to-r from-emerald-500 to-emerald-600 hover:from-emerald-600 hover:to-emerald-700 text-white py-3 rounded-xl font-semibold text-sm transition-all active:scale-[0.98] disabled:opacity-50 flex items-center justify-center gap-2"
                            >
                                {actionLoading === tx.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                                I've Arrived
                            </button>
                        )}
                        {tx.status === 'arrived' && (
                            <div className="flex-1 flex items-center justify-center gap-2 p-3 bg-emerald-500/5 border border-emerald-500/10 rounded-xl">
                                <Check className="h-4 w-4 text-emerald-400" />
                                <span className="text-sm text-emerald-400 font-medium">Waiting for operator to confirm delivery</span>
                            </div>
                        )}
                    </div>
                </div>
            </div>
        );
    };

    if (!driverId && !loading) {
        return (
            <div className="min-h-screen bg-dark-900 text-white flex items-center justify-center p-6">
                <div className="text-center max-w-sm">
                    <Car className="h-12 w-12 text-gray-700 mx-auto mb-3" />
                    <p className="text-gray-400 text-lg font-medium">No driver profile found</p>
                    <p className="text-gray-600 text-sm mt-1">Ask your company admin to assign you as a driver</p>
                </div>
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-dark-900 text-white pb-24">
            {/* ─── Header ─── */}
            <div className="bg-gradient-to-b from-brand-500/10 to-transparent">
                <div className="max-w-md mx-auto px-4 pt-6 pb-4">
                    <div className="flex items-center justify-between mb-1">
                        <div>
                            <p className="text-xs text-gray-500 uppercase tracking-wider">Driver Panel</p>
                            <h1 className="text-xl font-bold text-white">{driverName}</h1>
                        </div>
                        <button onClick={fetchTransactions} className="p-2 rounded-xl bg-dark-700/50 hover:bg-dark-600/50 transition-all active:scale-95">
                            <RefreshCw className="h-4 w-4 text-gray-400" />
                        </button>
                    </div>

                    {/* Stats row */}
                    <div className="flex gap-2 mt-3">
                        <div className="flex-1 bg-orange-500/10 border border-orange-500/10 rounded-xl p-2.5 text-center">
                            <p className="text-lg font-bold text-orange-400">{parkQueue.length}</p>
                            <p className="text-[9px] text-orange-400/60 uppercase">To Park</p>
                        </div>
                        <div className="flex-1 bg-purple-500/10 border border-purple-500/10 rounded-xl p-2.5 text-center">
                            <p className="text-lg font-bold text-purple-400">{retrieveQueue.length}</p>
                            <p className="text-[9px] text-purple-400/60 uppercase">To Retrieve</p>
                        </div>
                        <div className="flex-1 bg-brand-500/10 border border-brand-500/10 rounded-xl p-2.5 text-center">
                            <p className="text-lg font-bold text-brand-400">{recentlyParked.length}</p>
                            <p className="text-[9px] text-brand-400/60 uppercase">Parked</p>
                        </div>
                    </div>
                </div>
            </div>

            {/* ─── Tab Switcher ─── */}
            <div className="max-w-md mx-auto px-4 mt-2">
                <div className="flex gap-1 bg-dark-800/80 rounded-xl p-1 border border-white/5">
                    {[
                        { key: 'park', label: `🅿️ Park (${parkQueue.length})` },
                        { key: 'retrieve', label: `🔄 Retrieve (${retrieveQueue.length})` },
                    ].map(tab => (
                        <button
                            key={tab.key}
                            onClick={() => setActiveTab(tab.key)}
                            className={`flex-1 py-2.5 rounded-lg text-xs font-medium transition-all ${activeTab === tab.key
                                ? 'bg-brand-500 text-white shadow-lg shadow-brand-500/20'
                                : 'text-gray-400 hover:text-white'
                                }`}
                        >
                            {tab.label}
                        </button>
                    ))}
                </div>
            </div>

            {/* ─── Content ─── */}
            <div className="max-w-md mx-auto px-4 mt-4">
                {loading ? (
                    <div className="flex justify-center py-12">
                        <LoadingSpinner size="lg" />
                    </div>
                ) : activeTab === 'park' ? (
                    <>
                        {parkQueue.length === 0 && recentlyParked.length === 0 ? (
                            <div className="text-center py-12">
                                <Car className="h-10 w-10 text-gray-700 mx-auto mb-3" />
                                <p className="text-gray-500 text-sm">No parking tasks right now</p>
                                <p className="text-gray-600 text-xs mt-1">New assignments will appear here in real-time</p>
                            </div>
                        ) : (
                            <>
                                {parkQueue.length > 0 && (
                                    <div className="mb-4">
                                        <p className="text-xs text-orange-400 font-semibold uppercase tracking-wider mb-2">🟠 Waiting for you ({parkQueue.length})</p>
                                        {parkQueue.map(renderParkCard)}
                                    </div>
                                )}
                                {recentlyParked.length > 0 && (
                                    <div>
                                        <p className="text-xs text-brand-400 font-semibold uppercase tracking-wider mb-2">🅿️ Recently Parked ({recentlyParked.length})</p>
                                        {recentlyParked.map(renderParkedCard)}
                                    </div>
                                )}
                            </>
                        )}
                    </>
                ) : (
                    <>
                        {retrieveQueue.length === 0 ? (
                            <div className="text-center py-12">
                                <Car className="h-10 w-10 text-gray-700 mx-auto mb-3" />
                                <p className="text-gray-500 text-sm">No retrieval tasks</p>
                                <p className="text-gray-600 text-xs mt-1">Car retrieval assignments will appear here</p>
                            </div>
                        ) : (
                            retrieveQueue.map(renderRetrieveCard)
                        )}
                    </>
                )}
            </div>
            {/* Location Permission Modal */}
            {showPermissionModal && (
                <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
                    <div className="absolute inset-0 bg-dark-950/80 backdrop-blur-sm" onClick={() => setShowPermissionModal(false)} />
                    <div className="relative bg-dark-800 border border-white/10 p-6 rounded-3xl w-full max-w-sm shadow-2xl animate-in fade-in zoom-in duration-200">
                        <div className="bg-red-500/10 h-16 w-16 rounded-full flex items-center justify-center mb-6 mx-auto">
                            <MapPin className="h-8 w-8 text-red-400" />
                        </div>
                        <h3 className="text-xl font-bold text-white text-center mb-2">Location Required</h3>
                        <p className="text-gray-400 text-center text-sm mb-6">
                            We need your location to help navigate back to cars. Please enable location in your settings.
                        </p>

                        <div className="space-y-4 mb-8">
                            <div className="flex items-start gap-3">
                                <div className="bg-white/5 h-6 w-6 rounded-full flex items-center justify-center text-[10px] font-bold text-gray-400 mt-0.5">1</div>
                                <p className="text-xs text-gray-300">Tap the <span className="text-brand-400 font-bold">Compass icon</span> or <span className="text-brand-400 font-bold">"Aa"</span> in the address bar.</p>
                            </div>
                            <div className="flex items-start gap-3">
                                <div className="bg-white/5 h-6 w-6 rounded-full flex items-center justify-center text-[10px] font-bold text-gray-400 mt-0.5">2</div>
                                <p className="text-xs text-gray-300">Select <span className="text-brand-400 font-bold">Website Settings</span>.</p>
                            </div>
                            <div className="flex items-start gap-3">
                                <div className="bg-white/5 h-6 w-6 rounded-full flex items-center justify-center text-[10px] font-bold text-gray-400 mt-0.5">3</div>
                                <p className="text-xs text-gray-300">Change <span className="text-brand-400 font-bold">Location</span> to <span className="text-emerald-400 font-bold">Allow</span>.</p>
                            </div>
                        </div>

                        <button
                            onClick={() => setShowPermissionModal(false)}
                            className="w-full bg-white text-black py-4 rounded-2xl font-bold text-sm hover:bg-gray-200 transition-colors"
                        >
                            Got it, I'll fix it
                        </button>
                    </div>
                </div>
            )}
        </div>
    );
};

export default DriverPanel;
