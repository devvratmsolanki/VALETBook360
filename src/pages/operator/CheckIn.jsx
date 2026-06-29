import { useState, useEffect, useRef } from 'react';
import { Phone, User, Car as CarIcon, Camera, MapPin, Wrench, Search, UserCheck, RefreshCw } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Select from '../../components/ui/Select';
import { toast } from '../../components/ui/Toast';
import { useAuth } from '../../contexts/AuthContext';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import DriverSelect from '../../components/shared/DriverSelect';
import { searchVisitorByPhone, getVisitorByPhone, createVisitor } from '../../services/visitorService';
import { findCarByNumber, createCar } from '../../services/carService';
import { createTransaction, getActiveTransactions, getNextAvailableKeySlot } from '../../services/transactionService';
import { getLocationSlotNames } from '../../services/slotService';
import { getLocationsByCompany } from '../../services/locationService';
import { cn } from '../../lib/utils';
import logger from '../../lib/logger';

const CheckIn = () => {
    const { companyId } = useAuth();
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
    const [locations, setLocations] = useState([]);
    // Key-slot auto-allocation: the location's ordered pool, the occupied set
    // (active cars' key codes), and the currently-selected slot (auto-defaulted
    // to the lowest free slot; the operator can tap another free box to override).
    const [slotNames, setSlotNames] = useState([]);
    const [occupiedSlots, setOccupiedSlots] = useState(new Set());
    const [keyCode, setKeyCode] = useState('');
    const dropdownRef = useRef(null);
    const fileInputRef = useRef(null);

    // Load the selected location's slot pool + occupancy and auto-pick the next
    // free slot. Runs whenever the chosen location changes (and after a check-in,
    // so the freshly-used slot greys out and the default advances).
    const loadSlots = async (locationId) => {
        if (!locationId) {
            setSlotNames([]); setOccupiedSlots(new Set()); setKeyCode('');
            return;
        }
        try {
            const [names, nextSlot, activeTxs] = await Promise.all([
                getLocationSlotNames(locationId),
                getNextAvailableKeySlot(locationId),
                getActiveTransactions(companyId),
            ]);
            setSlotNames(names);
            setOccupiedSlots(new Set(
                activeTxs
                    .filter(t => t.location_id === locationId && t.key_code &&
                        !['delivered', 'cancelled'].includes(t.status))
                    .map(t => t.key_code)
            ));
            setKeyCode(nextSlot || '');
        } catch (err) {
            logger.error('Error loading key slots:', err);
        }
    };

    // (Re)load slots when the location or company becomes available.
    useEffect(() => {
        loadSlots(selectedLocationId);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [selectedLocationId, companyId]);

    // Fetch locations
    useEffect(() => {
        const fetchLocations = async () => {
            try {
                if (companyId) {
                    const locationList = await getLocationsByCompany(companyId);
                    setLocations(locationList);
                }
            } catch (err) {
                logger.error('Error loading locations:', err);
            }
        };
        fetchLocations();
    }, [companyId]);

    // Phone search — trigger after 7 digits
    useEffect(() => {
        const digitsOnly = phone.replace(/\D/g, '');
        if (digitsOnly.length < 7) {
            setSearchResults([]);
            setShowDropdown(false);
            return;
        }
        const timer = setTimeout(async () => {
            try {
                const results = await searchVisitorByPhone(phone);
                setSearchResults(results);
                setShowDropdown(results.length > 0);
            } catch (err) {
                logger.error('Search error:', err);
            }
        }, 300);
        return () => clearTimeout(timer);
    }, [phone]);

    useEffect(() => {
        const handleClick = (e) => {
            if (dropdownRef.current && !dropdownRef.current.contains(e.target)) setShowDropdown(false);
        };
        document.addEventListener('mousedown', handleClick);
        return () => document.removeEventListener('mousedown', handleClick);
    }, []);

    const selectVisitor = async (visitor) => {
        setPhone(visitor.phone);
        setName(visitor.name);
        setExistingVisitor(visitor);
        setIsReturning(true);
        setShowDropdown(false);
        try {
            const fullData = await getVisitorByPhone(visitor.phone);
            if (fullData?.cars?.length > 0) {
                const lastCar = fullData.cars[fullData.cars.length - 1];
                setCarNumber(lastCar.car_number || '');
                setCarMake(`${lastCar.make || ''} ${lastCar.model || ''}`.trim());
            }
        } catch (err) {
            logger.error('Error fetching visitor details:', err);
        }
    };

    const handleLocationChange = (val) => {
        setSelectedLocationId(val);
        if (val) localStorage.setItem('vb360_last_location', val);
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        if (!phone || !name || !carNumber) {
            toast.error('Please fill in all required fields');
            return;
        }
        if (!selectedDriver) {
            toast.error('Please select a driver');
            return;
        }
        if (slotNames.length > 0 && !keyCode) {
            toast.error('Please assign a key slot');
            return;
        }
        if (keyCode && occupiedSlots.has(keyCode)) {
            toast.error(`Slot ${keyCode} was just taken — pick another`);
            loadSlots(selectedLocationId);
            return;
        }
        setLoading(true);
        try {
            let visitorId;
            if (existingVisitor) {
                visitorId = existingVisitor.id;
            } else {
                const nv = await createVisitor({ name, phone });
                visitorId = nv.id;
            }

            let carId;
            const existingCar = await findCarByNumber(carNumber.toUpperCase());
            if (existingCar) {
                carId = existingCar.id;
            } else {
                const [make, ...modelParts] = (carMake || '').split(' ');
                const nc = await createCar({
                    car_number: carNumber.toUpperCase(),
                    visitor_id: visitorId,
                    make: make || null,
                    model: modelParts.join(' ') || null,
                });
                carId = nc.id;
            }

            const txData = {
                visitor_id: visitorId,
                car_id: carId,
                parking_slot: parkingLocation || null,
                key_code: keyCode || null,
                status: 'parked',
                valet_company_id: companyId || null,
            };
            if (selectedDriver) txData.parked_by_driver_id = selectedDriver;
            if (selectedLocationId) txData.location_id = selectedLocationId;

            await createTransaction(txData);

            // Trigger n8n webhook
            const webhookUrl = import.meta.env.VITE_N8N_WEBHOOK_URL;
            if (webhookUrl && webhookUrl !== 'your_n8n_webhook_url_here') {
                try {
                    await fetch(webhookUrl, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            event: 'car_parked',
                            guest_name: name,
                            phone,
                            car_number: carNumber.toUpperCase(),
                            parking_slot: parkingLocation,
                        }),
                    });
                } catch (webhookErr) {
                    logger.warn('Webhook call failed:', webhookErr);
                }
            }

            toast.success('Vehicle checked in successfully!');
            setPhone(''); setName(''); setCarNumber(''); setCarMake('');
            setParkingLocation(''); setSelectedDriver('');
            setExistingVisitor(null); setIsReturning(false);
            // Keep the location and refresh the pool so the just-used slot greys
            // out and the next free slot auto-selects for the next car.
            loadSlots(selectedLocationId);
        } catch (err) {
            toast.error(err.message || 'Failed to check in vehicle');
        } finally {
            setLoading(false);
        }
    };

    const locationOptions = [{ value: '', label: 'Select location...' }, ...locations.map(l => ({ value: l.id, label: l.name }))];

    return (
        <div className="max-w-2xl mx-auto animate-fade-in">
            <div className="mb-8">
                <h1 className="text-2xl font-bold text-white">Check In Vehicle</h1>
                <p className="text-sm text-gray-500 mt-1">Register a new vehicle arrival</p>
            </div>

            <Card className="p-6 lg:p-8 relative overflow-hidden">
                <div className="absolute top-0 left-0 w-full h-px bg-gradient-to-r from-transparent via-brand-500/30 to-transparent" />
                <form onSubmit={handleSubmit} className="space-y-5">
                    {/* Location — TOP of form */}
                    {locations.length > 0 && (
                        <Select
                            label={<span className="flex items-center gap-2"><MapPin className="h-3.5 w-3.5 text-brand-500" /> Service Location</span>}
                            options={locationOptions}
                            value={selectedLocationId}
                            onChange={(e) => handleLocationChange(e.target.value)}
                        />
                    )}

                    {/* Phone */}
                    <div className="space-y-1.5" ref={dropdownRef}>
                        <label className="flex items-center gap-2 text-sm font-medium text-gray-300">
                            <Phone className="h-3.5 w-3.5 text-brand-500" /> Phone Number <span className="text-red-400">*</span>
                            <span className="text-xs text-gray-600 ml-auto">Search starts after 7 digits</span>
                        </label>
                        <div className="relative">
                            <div className="relative group">
                                <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500 group-focus-within:text-brand-500 transition-colors" />
                                <input type="tel" value={phone} onChange={(e) => { setPhone(e.target.value); setExistingVisitor(null); setIsReturning(false); }}
                                    placeholder="+91XXXXXXXXXX" required
                                    className="block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-4 text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all" />
                            </div>
                            {showDropdown && (
                                <div className="absolute z-10 w-full mt-1 bg-dark-700 border border-white/10 rounded-xl shadow-2xl overflow-hidden">
                                    {searchResults.map((v) => (
                                        <button key={v.id} type="button" onClick={() => selectVisitor(v)}
                                            className="w-full px-4 py-3 text-left hover:bg-brand-500/10 transition-colors border-b border-white/5 last:border-0">
                                            <p className="text-sm font-medium text-white">{v.name}</p>
                                            <p className="text-xs text-gray-400">{v.phone}</p>
                                        </button>
                                    ))}
                                </div>
                            )}
                        </div>
                        {isReturning && <p className="text-xs text-emerald-400 flex items-center gap-1">✓ Returning visitor — details auto-filled</p>}
                    </div>

                    {/* Name */}
                    <div className="space-y-1.5">
                        <label className="flex items-center gap-2 text-sm font-medium text-gray-300">
                            <User className="h-3.5 w-3.5 text-brand-500" /> Guest Name <span className="text-red-400">*</span>
                        </label>
                        <div className="relative group">
                            <User className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500 group-focus-within:text-brand-500 transition-colors" />
                            <input type="text" value={name} onChange={(e) => setName(e.target.value)}
                                placeholder="Enter guest name" required
                                className="block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-4 text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all" />
                        </div>
                    </div>

                    {/* Car Number + Camera */}
                    <div className="space-y-1.5">
                        <label className="flex items-center gap-2 text-sm font-medium text-gray-300">
                            <CarIcon className="h-3.5 w-3.5 text-brand-500" /> Car Number <span className="text-red-400">*</span>
                        </label>
                        <div className="flex gap-2">
                            <div className="relative group flex-1">
                                <CarIcon className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500 group-focus-within:text-brand-500 transition-colors" />
                                <input type="text" value={carNumber} onChange={(e) => setCarNumber(e.target.value.toUpperCase())}
                                    placeholder="MH01AB1234" required
                                    className="block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-4 text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all uppercase" />
                            </div>
                            <button type="button" onClick={() => fileInputRef.current?.click()}
                                className="flex items-center gap-2 px-4 py-3 rounded-xl bg-dark-600 border border-white/5 text-gray-400 hover:text-brand-400 hover:border-brand-500/20 transition-all">
                                <Camera className="h-5 w-5" />
                            </button>
                            <input ref={fileInputRef} type="file" accept="image/*" capture="environment"
                                onChange={() => toast.info('Please verify the captured plate number')} className="hidden" />
                        </div>
                    </div>

                    {/* Car Make */}
                    <div className="space-y-1.5">
                        <label className="flex items-center gap-2 text-sm font-medium text-gray-300">
                            <Wrench className="h-3.5 w-3.5 text-gray-500" /> Car Make / Model <span className="text-gray-600 text-xs">(optional)</span>
                        </label>
                        <div className="relative group">
                            <Wrench className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500 group-focus-within:text-brand-500 transition-colors" />
                            <input type="text" value={carMake} onChange={(e) => setCarMake(e.target.value)}
                                placeholder="Toyota Camry"
                                className="block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-4 text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all" />
                        </div>
                    </div>

                    {/* Parking Slot */}
                    <div className="space-y-1.5">
                        <label className="flex items-center gap-2 text-sm font-medium text-gray-300">
                            <MapPin className="h-3.5 w-3.5 text-gray-500" /> Parking Slot <span className="text-gray-600 text-xs">(optional)</span>
                        </label>
                        <div className="relative group">
                            <MapPin className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500 group-focus-within:text-brand-500 transition-colors" />
                            <input type="text" value={parkingLocation} onChange={(e) => setParkingLocation(e.target.value)}
                                placeholder="B2-Slot 14"
                                className="block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-4 text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all" />
                        </div>
                    </div>

                    {/* Key Slot — auto-allocated to lowest free, tap to override */}
                    {selectedLocationId && (
                        <div className="space-y-1.5">
                            <label className="flex items-center justify-between text-sm font-medium text-gray-300">
                                <span className="flex items-center gap-2">🔑 Key Slot <span className="text-red-400">*</span></span>
                                <span className="flex items-center gap-2 text-[11px] font-normal text-gray-500">
                                    {keyCode ? <span className="text-brand-400 font-semibold">Auto: {keyCode}</span> : 'Pick a slot'}
                                    {slotNames.length > 0 && <span>• {slotNames.length} total</span>}
                                    <button type="button" onClick={() => loadSlots(selectedLocationId)} className="p-1 rounded-md hover:bg-white/5 text-gray-500 hover:text-white transition-colors" title="Refresh slots & re-pick">
                                        <RefreshCw className="h-3 w-3" />
                                    </button>
                                </span>
                            </label>
                            {slotNames.length === 0 ? (
                                <div className="rounded-xl border border-amber-500/20 bg-amber-500/5 p-3 text-xs text-amber-400">
                                    No key slots configured for this location. Set a key capacity or add slots in the location settings.
                                </div>
                            ) : (
                                <div className="grid grid-cols-5 sm:grid-cols-6 gap-1.5 max-h-44 overflow-y-auto pr-1 rounded-xl border border-white/5 bg-dark-700/40 p-2">
                                    {slotNames.map((slotName) => {
                                        const isOccupied = occupiedSlots.has(slotName);
                                        const isSelected = keyCode === slotName;
                                        return (
                                            <button
                                                key={slotName}
                                                type="button"
                                                disabled={isOccupied}
                                                onClick={() => setKeyCode(slotName)}
                                                aria-label={`Key slot ${slotName}${isOccupied ? ' (occupied)' : isSelected ? ' (selected)' : ' (free)'}`}
                                                aria-pressed={isSelected}
                                                title={isOccupied ? `Slot ${slotName} is occupied` : `Assign slot ${slotName}`}
                                                className={cn(
                                                    'aspect-square rounded-lg border text-xs font-bold flex items-center justify-center px-1 truncate transition-all',
                                                    isOccupied
                                                        ? 'bg-dark-700 border-white/5 text-gray-600 opacity-40 cursor-not-allowed line-through'
                                                        : isSelected
                                                            ? 'bg-brand-500 text-black border-brand-400 shadow-lg shadow-brand-500/20 scale-105'
                                                            : 'bg-dark-600 border-white/5 text-gray-300 hover:border-brand-500/40 hover:text-brand-400'
                                                )}
                                            >
                                                {slotName}
                                            </button>
                                        );
                                    })}
                                </div>
                            )}
                        </div>
                    )}

                    {/* Driver Select */}
                    <DriverSelect
                        companyId={companyId}
                        value={selectedDriver}
                        onChange={(e) => setSelectedDriver(e.target.value)}
                        required
                    />

                    {/* Submit */}
                    <Button type="submit" size="lg" className="w-full mt-4" disabled={loading}>
                        {loading ? (
                            <span className="flex items-center gap-2">
                                <LoadingSpinner size="sm" color="white" />
                                Checking In...
                            </span>
                        ) : (
                            <span className="flex items-center gap-2"><CarIcon className="h-4 w-4" /> Park Vehicle</span>
                        )}
                    </Button>
                </form>
            </Card>
        </div>
    );
};

export default CheckIn;
