import { useState, useEffect, useMemo } from 'react';
import { getActiveTransactions, subscribeToTransactions, updateTransactionStatus, assignDriverForRetrieval } from '../../services/transactionService';
import { sendDriverAssigned, sendCarReady, sendCarDelivered } from '../../services/webhookService';
import { getDriversByCompany } from '../../services/driverService';
import { useAuth } from '../../contexts/AuthContext';
import Card from '../../components/ui/Card';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Modal from '../../components/ui/Modal';
import { toast } from '../../components/ui/Toast';
import { formatTime, parseUTC } from '../../lib/utils';
import { Car, Clock, RefreshCw, UserCheck, Timer, Send, MapPin } from 'lucide-react';

const ActiveCars = () => {
    const { companyId, companyName } = useAuth();
    const [transactions, setTransactions] = useState([]);
    const [loading, setLoading] = useState(true);
    const [drivers, setDrivers] = useState([]);

    // Retrieval assignment modal
    const [showAssignModal, setShowAssignModal] = useState(false);
    const [selectedTx, setSelectedTx] = useState(null);
    const [assignDriverId, setAssignDriverId] = useState('');
    const [etaMinutes, setEtaMinutes] = useState(8);
    const [assigning, setAssigning] = useState(false);

    const fetchData = async () => {
        try {
            const [txs, driverList] = await Promise.all([
                getActiveTransactions(companyId),
                companyId ? getDriversByCompany(companyId) : Promise.resolve([]),
            ]);
            setTransactions(txs);
            setDrivers(driverList.filter(d => d.active));
        } catch (err) {
            toast.error('Failed to load active cars');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
        const sub = subscribeToTransactions(() => fetchData());
        return () => sub.unsubscribe();
    }, [companyId]);

    // FCFS: Open assignment modal for car retrieval
    const openAssignModal = (tx) => {
        setSelectedTx(tx);
        // Default: same driver who parked the car
        setAssignDriverId(tx.parked_by_driver_id || '');
        setEtaMinutes(8);
        setShowAssignModal(true);
    };

    const handleAssignDriver = async () => {
        if (!assignDriverId) {
            toast.error('Please select a driver');
            return;
        }
        setAssigning(true);
        try {
            await assignDriverForRetrieval(selectedTx.id, assignDriverId, etaMinutes);

            // Send WhatsApp notification via centralized service
            const driver = drivers.find(d => d.id === assignDriverId);
            const now = new Date();
            const eta = new Date(now.getTime() + etaMinutes * 60 * 1000);

            sendDriverAssigned({
                guest_name: selectedTx.visitors?.name,
                phone: selectedTx.visitors?.phone,
                car_number: selectedTx.cars?.car_number,
                driver_name: driver?.name,
                eta_minutes: etaMinutes,
                estimated_time: eta.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
                company_name: companyName,
                transaction_id: selectedTx.id,
            });

            toast.success(`Driver assigned! ETA: ${etaMinutes} mins`);
            setShowAssignModal(false);
            setSelectedTx(null);
            fetchData();
        } catch (err) {
            toast.error('Failed to assign driver');
        } finally {
            setAssigning(false);
        }
    };

    const handleStatusUpdate = async (id, newStatus) => {
        const prev = [...transactions];
        setTransactions(transactions.map(t => t.id === id ? { ...t, status: newStatus } : t));
        try {
            await updateTransactionStatus(id, newStatus);
            const tx = transactions.find(t => t.id === id);

            if (newStatus === 'ready' && tx) {
                sendCarReady({
                    guest_name: tx.visitors?.name,
                    phone: tx.visitors?.phone,
                    car_number: tx.cars?.car_number,
                    driver_name: tx.retrieved_driver?.name || tx.parked_driver?.name,
                    company_name: companyName,
                    transaction_id: id,
                });
            }

            if (newStatus === 'delivered' && tx) {
                sendCarDelivered({
                    guest_name: tx.visitors?.name,
                    phone: tx.visitors?.phone,
                    car_number: tx.cars?.car_number,
                    company_name: companyName,
                    transaction_id: id,
                });
            }

            toast.success(`Status updated to ${newStatus}`);
        } catch {
            setTransactions(prev);
            toast.error('Failed to update status');
        }
    };

    const statusCounts = {
        parked: transactions.filter(t => t.status === 'parked').length,
        requested: transactions.filter(t => t.status === 'requested').length,
        ready: transactions.filter(t => t.status === 'ready').length,
    };

    // Sort: requested first (FCFS), then parked, then ready
    const sortedTransactions = [...transactions].sort((a, b) => {
        const statusOrder = { requested: 0, parked: 1, ready: 2 };
        const diff = (statusOrder[a.status] ?? 3) - (statusOrder[b.status] ?? 3);
        if (diff !== 0) return diff;
        return parseUTC(a.created_at) - parseUTC(b.created_at); // FCFS: oldest first within same status
    });

    const getEtaDisplay = (tx) => {
        if (!tx.estimated_delivery_time) return null;
        const eta = parseUTC(tx.estimated_delivery_time);
        const now = new Date();
        const minsLeft = Math.max(0, Math.round((eta - now) / 60000));
        return { time: eta.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }), minsLeft };
    };

    return (
        <div className="animate-fade-in">
            <div className="flex items-center justify-between mb-6">
                <div>
                    <h1 className="text-2xl font-bold text-white">Active Cars</h1>
                    <p className="text-sm text-gray-500 mt-1">{transactions.length} vehicles currently active</p>
                </div>
                <Button variant="ghost" onClick={fetchData}><RefreshCw className="h-4 w-4" /> Refresh</Button>
            </div>

            {/* Status Counts */}
            <div className="grid grid-cols-3 gap-3 mb-6">
                <Card className="p-4 text-center"><p className="text-2xl font-bold text-brand-400">{statusCounts.parked}</p><p className="text-xs text-gray-500 mt-1">Parked</p></Card>
                <Card className="p-4 text-center"><p className="text-2xl font-bold text-amber-400">{statusCounts.requested}</p><p className="text-xs text-gray-500 mt-1">Requested</p></Card>
                <Card className="p-4 text-center"><p className="text-2xl font-bold text-emerald-400">{statusCounts.ready}</p><p className="text-xs text-gray-500 mt-1">Ready</p></Card>
            </div>

            {/* Transaction List */}
            <div className="space-y-3">
                {loading ? (
                    <Card className="p-8 text-center"><div className="animate-spin h-6 w-6 border-2 border-brand-500 border-t-transparent rounded-full mx-auto" /><p className="text-gray-500 mt-3 text-sm">Loading...</p></Card>
                ) : sortedTransactions.length === 0 ? (
                    <Card className="p-8 text-center"><Car className="h-8 w-8 text-gray-600 mx-auto mb-3" /><p className="text-gray-500 text-sm">No active cars</p></Card>
                ) : (
                    sortedTransactions.map((tx) => {
                        const eta = getEtaDisplay(tx);
                        return (
                            <Card key={tx.id} className={`p-4 ${tx.status === 'requested' ? 'border-amber-500/20 brand-glow' : ''}`}>
                                <div className="flex items-start justify-between">
                                    <div className="flex items-start gap-4">
                                        <div className="bg-dark-600 p-2.5 rounded-xl"><Car className="h-5 w-5 text-brand-500" /></div>
                                        <div>
                                            <p className="font-semibold text-white text-sm">
                                                {tx.cars?.car_number || 'Unknown'}
                                                {tx.cars?.make && <span className="text-gray-500 font-normal ml-2 text-xs">{tx.cars.make} {tx.cars.model}</span>}
                                            </p>
                                            <p className="text-sm text-gray-400 mt-0.5">{tx.visitors?.name || 'Unknown Guest'}</p>
                                            <div className="flex items-center gap-3 mt-2 flex-wrap">
                                                <span className="text-xs text-gray-500 flex items-center gap-1"><Clock className="h-3 w-3" /> {formatTime(tx.created_at)}</span>
                                                {tx.parking_slot && <span className="text-xs text-gray-500">Slot: {tx.parking_slot}</span>}
                                                {tx.key_code && <span className="text-xs text-brand-400 font-medium flex items-center gap-1">🔑 {tx.key_code}</span>}
                                                {tx.locations && <span className="text-xs text-purple-400 flex items-center gap-1"><MapPin className="h-3 w-3" />{tx.locations.name}</span>}
                                                {tx.parked_driver && <span className="text-xs text-blue-400 flex items-center gap-1"><UserCheck className="h-3 w-3" /> Parked by: {tx.parked_driver.name}</span>}
                                                {tx.retrieved_driver && <span className="text-xs text-emerald-400 flex items-center gap-1"><UserCheck className="h-3 w-3" /> Retrieving: {tx.retrieved_driver.name}</span>}
                                            </div>
                                            {eta && tx.status === 'requested' && (
                                                <div className="flex items-center gap-2 mt-2 px-2 py-1 bg-amber-500/10 rounded-lg w-fit">
                                                    <Timer className="h-3.5 w-3.5 text-amber-400" />
                                                    <span className="text-xs text-amber-400 font-medium">
                                                        ETA: {eta.minsLeft > 0 ? `${eta.minsLeft} min left` : 'Due now'} (by {eta.time})
                                                    </span>
                                                </div>
                                            )}
                                        </div>
                                    </div>
                                    <div className="flex items-center gap-2">
                                        <Badge variant={tx.status}>{tx.status}</Badge>
                                        {tx.status === 'parked' && (
                                            <Button size="sm" variant="outline" onClick={() => openAssignModal(tx)}>
                                                <Send className="h-3.5 w-3.5" /> Request
                                            </Button>
                                        )}
                                        {tx.status === 'requested' && (
                                            <Button size="sm" variant="outline" className="border-emerald-500/30 text-emerald-400 hover:bg-emerald-500/10"
                                                onClick={() => handleStatusUpdate(tx.id, 'ready')}>Ready</Button>
                                        )}
                                        {tx.status === 'ready' && (
                                            <Button size="sm" variant="ghost" onClick={() => handleStatusUpdate(tx.id, 'delivered')}>Delivered</Button>
                                        )}
                                    </div>
                                </div>
                            </Card>
                        );
                    })
                )}
            </div>

            {/* Driver Assignment Modal */}
            <Modal isOpen={showAssignModal} onClose={() => setShowAssignModal(false)} title="Assign Driver for Retrieval">
                {selectedTx && (
                    <div className="space-y-4">
                        <div className="bg-dark-600 rounded-xl p-4">
                            <p className="text-sm font-medium text-white">{selectedTx.cars?.car_number}</p>
                            <p className="text-xs text-gray-400 mt-1">Guest: {selectedTx.visitors?.name} • {selectedTx.visitors?.phone}</p>
                            {selectedTx.parked_driver && (
                                <p className="text-xs text-blue-400 mt-1 flex items-center gap-1">
                                    <UserCheck className="h-3 w-3" /> Originally parked by: {selectedTx.parked_driver.name}
                                </p>
                            )}
                        </div>

                        <div className="space-y-1.5">
                            <label className="text-sm font-medium text-gray-300 flex items-center gap-2">
                                <UserCheck className="h-3.5 w-3.5 text-brand-500" /> Select Driver
                            </label>
                            <select value={assignDriverId} onChange={(e) => setAssignDriverId(e.target.value)}
                                className="block w-full appearance-none rounded-xl border-0 bg-dark-600 py-3 pl-4 pr-10 text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all">
                                <option value="">Select a driver...</option>
                                {drivers.map(d => (
                                    <option key={d.id} value={d.id}>
                                        {d.name} {d.id === selectedTx.parked_by_driver_id ? '(Same driver ✓)' : ''}
                                    </option>
                                ))}
                            </select>
                            {selectedTx.parked_by_driver_id && assignDriverId !== selectedTx.parked_by_driver_id && assignDriverId && (
                                <p className="text-xs text-amber-400">⚠ Different driver from who parked the car</p>
                            )}
                        </div>

                        <div className="space-y-1.5">
                            <label className="text-sm font-medium text-gray-300 flex items-center gap-2">
                                <Timer className="h-3.5 w-3.5 text-brand-500" /> ETA (minutes)
                            </label>
                            <input type="number" min="1" max="60" value={etaMinutes} onChange={(e) => setEtaMinutes(parseInt(e.target.value) || 8)}
                                className="block w-full rounded-xl border-0 bg-dark-600 py-3 px-4 text-gray-200 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all" />
                            <p className="text-xs text-gray-500">
                                Guest will receive: "Your car will arrive by {formatTime(new Date(Date.now() + etaMinutes * 60 * 1000).toISOString())}"
                            </p>
                        </div>

                        <div className="flex justify-end gap-3 pt-2">
                            <Button variant="ghost" onClick={() => setShowAssignModal(false)}>Cancel</Button>
                            <Button onClick={handleAssignDriver} disabled={assigning}>
                                {assigning ? 'Assigning...' : (<><Send className="h-4 w-4" /> Assign & Notify</>)}
                            </Button>
                        </div>
                    </div>
                )}
            </Modal>
        </div>
    );
};

export default ActiveCars;
