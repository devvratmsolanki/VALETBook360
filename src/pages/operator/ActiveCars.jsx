import { useState, useEffect, useMemo } from 'react';
import { getActiveTransactions, subscribeToTransactions, updateTransactionStatus, assignDriverForRetrieval } from '../../services/transactionService';
import { sendDriverAssigned, sendCarReady, sendCarDelivered } from '../../services/webhookService';
import { getDriversByCompany } from '../../services/driverService';
import { useAuth } from '../../contexts/AuthContext';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
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
            setTransactions(txs || []);
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

    const openAssignModal = (tx) => {
        setSelectedTx(tx);
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

    const sortedTransactions = [...transactions].sort((a, b) => {
        const statusOrder = { requested: 0, parked: 1, ready: 2 };
        const diff = (statusOrder[a.status] ?? 3) - (statusOrder[b.status] ?? 3);
        if (diff !== 0) return diff;
        return parseUTC(a.created_at) - parseUTC(b.created_at);
    });

    const getEtaDisplay = (tx) => {
        if (!tx.estimated_delivery_time) return null;
        const eta = parseUTC(tx.estimated_delivery_time);
        const now = new Date();
        const minsLeft = Math.max(0, Math.round((eta - now) / 60000));
        return { time: eta.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }), minsLeft };
    };

    if (loading) {
        return (
            <div className="flex flex-col items-center justify-center h-64">
                <LoadingSpinner size="lg" />
                <p className="text-gray-500 mt-4 text-sm font-medium">Loading active vehicles...</p>
            </div>
        );
    }

    return (
        <div className="animate-fade-in">
            <div className="flex items-center justify-between mb-6">
                <div>
                    <h1 className="text-2xl font-bold text-white">Active Cars</h1>
                    <p className="text-sm text-gray-500 mt-1">{transactions.length} vehicles currently active</p>
                </div>
                <Button variant="ghost" onClick={fetchData} className="hover:bg-brand-500/10 text-brand-400">
                    <RefreshCw className="h-4 w-4 mr-2" /> Refresh
                </Button>
            </div>

            <div className="grid grid-cols-3 gap-3 mb-6">
                <Card className="p-4 text-center bg-brand-500/5 border-brand-500/10"><p className="text-2xl font-bold text-brand-400">{statusCounts.parked}</p><p className="text-[10px] uppercase text-gray-500 font-semibold mt-1 tracking-wider">Parked</p></Card>
                <Card className="p-4 text-center bg-amber-500/5 border-amber-500/10"><p className="text-2xl font-bold text-amber-400">{statusCounts.requested}</p><p className="text-[10px] uppercase text-gray-500 font-semibold mt-1 tracking-wider">Requested</p></Card>
                <Card className="p-4 text-center bg-emerald-500/5 border-emerald-500/10"><p className="text-2xl font-bold text-emerald-400">{statusCounts.ready}</p><p className="text-[10px] uppercase text-gray-500 font-semibold mt-1 tracking-wider">Ready</p></Card>
            </div>

            <div className="space-y-3">
                {sortedTransactions.length === 0 ? (
                    <Card className="p-12 text-center bg-dark-800/50 border-dashed">
                        <Car className="h-10 w-10 text-gray-700 mx-auto mb-3" />
                        <p className="text-gray-500 text-sm">No vehicles active at the moment</p>
                    </Card>
                ) : (
                    sortedTransactions.map((tx) => {
                        const eta = getEtaDisplay(tx);
                        return (
                            <Card key={tx.id} className={`p-4 transition-all duration-300 ${tx.status === 'requested' ? 'border-amber-500/30 bg-amber-500/5 ring-1 ring-amber-500/20' : 'hover:border-white/10'}`}>
                                <div className="flex items-start justify-between">
                                    <div className="flex items-start gap-4">
                                        <div className="bg-dark-600 p-2.5 rounded-xl border border-white/5"><Car className="h-5 w-5 text-brand-500" /></div>
                                        <div>
                                            <p className="font-bold text-white text-base">
                                                {tx.cars?.car_number || 'Unknown'}
                                                {tx.cars?.make && <span className="text-gray-500 font-normal ml-2 text-xs uppercase tracking-tighter">{tx.cars.make} {tx.cars.model}</span>}
                                            </p>
                                            <p className="text-sm text-gray-400 mt-0.5">{tx.visitors?.name || 'Unknown Guest'}</p>
                                            <div className="flex items-center gap-3 mt-3 flex-wrap">
                                                <span className="text-[10px] text-gray-500 flex items-center gap-1 bg-white/5 px-2 py-1 rounded-lg"><Clock className="h-3 w-3" /> {formatTime(tx.created_at)}</span>
                                                {tx.parking_slot && <span className="text-[10px] text-gray-500 bg-white/5 px-2 py-1 rounded-lg">Slot: {tx.parking_slot}</span>}
                                                {tx.key_code && <span className="text-[10px] text-brand-400 font-bold flex items-center gap-1 bg-brand-500/10 px-2 py-1 rounded-lg border border-brand-500/20">🔑 {tx.key_code}</span>}
                                                {tx.locations && <span className="text-[10px] text-purple-400 flex items-center gap-1 bg-purple-500/10 px-2 py-1 rounded-lg border border-purple-500/20"><MapPin className="h-3 w-3" />{tx.locations.name}</span>}
                                            </div>
                                            {eta && tx.status === 'requested' && (
                                                <div className="flex items-center gap-2 mt-3 px-3 py-1.5 bg-amber-500/20 border border-amber-500/20 rounded-xl w-fit animate-pulse">
                                                    <Timer className="h-3.5 w-3.5 text-amber-400" />
                                                    <span className="text-xs text-amber-300 font-bold">
                                                        ETA: {eta.minsLeft > 0 ? `${eta.minsLeft}m left` : 'Due now'} (by {eta.time})
                                                    </span>
                                                </div>
                                            )}
                                        </div>
                                    </div>
                                    <div className="flex flex-col items-end gap-3">
                                        <Badge variant={tx.status} className="uppercase font-bold tracking-wider">{tx.status}</Badge>
                                        <div className="flex items-center gap-2 mt-1">
                                            {tx.status === 'parked' && (
                                                <Button size="sm" variant="outline" onClick={() => openAssignModal(tx)} className="text-[10px] py-1 h-8">
                                                    <Send className="h-3 w-3 mr-1.5" /> Request
                                                </Button>
                                            )}
                                            {tx.status === 'requested' && (
                                                <Button size="sm" variant="outline" className="border-emerald-500/30 text-emerald-400 hover:bg-emerald-500/10 text-[10px] py-1 h-8"
                                                    onClick={() => handleStatusUpdate(tx.id, 'ready')}>Mark Ready</Button>
                                            )}
                                            {tx.status === 'ready' && (
                                                <Button size="sm" variant="ghost" onClick={() => handleStatusUpdate(tx.id, 'delivered')} className="text-[10px] py-1 h-8 hover:bg-white/5">Deliver</Button>
                                            )}
                                        </div>
                                    </div>
                                </div>
                            </Card>
                        );
                    })
                )}
            </div>

            <Modal isOpen={showAssignModal} onClose={() => setShowAssignModal(false)} title="Assign Retrieval Task">
                {selectedTx && (
                    <div className="space-y-5">
                        <Card className="bg-dark-600/50 p-4 border-white/5">
                            <div className="flex items-center justify-between">
                                <div>
                                    <p className="text-lg font-bold text-white tracking-widest">{selectedTx.cars?.car_number}</p>
                                    <p className="text-xs text-brand-400 mt-1 uppercase font-semibold">Guest: {selectedTx.visitors?.name}</p>
                                </div>
                                <div className="text-right">
                                    <p className="text-[10px] text-gray-500 uppercase font-bold">Key Slot</p>
                                    <p className="text-base font-bold text-amber-400">🔑 {selectedTx.key_code || 'N/A'}</p>
                                </div>
                            </div>
                        </Card>

                        <div className="space-y-2">
                            <label className="text-xs font-bold text-gray-500 uppercase flex items-center gap-2">
                                <UserCheck className="h-3.5 w-3.5 text-brand-500" /> Assign Driver
                            </label>
                            <select value={assignDriverId} onChange={(e) => setAssignDriverId(e.target.value)}
                                className="block w-full appearance-none rounded-2xl border-0 bg-dark-600 py-3.5 px-4 text-gray-200 ring-1 ring-white/10 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all focus:bg-dark-500">
                                <option value="">Select a driver...</option>
                                {drivers.map(d => (
                                    <option key={d.id} value={d.id}>
                                        {d.name} {d.id === selectedTx.parked_by_driver_id ? '(Same as Park driver ✓)' : ''}
                                    </option>
                                ))}
                            </select>
                        </div>

                        <div className="space-y-2">
                            <label className="text-xs font-bold text-gray-500 uppercase flex items-center gap-2">
                                <Timer className="h-3.5 w-3.5 text-brand-500" /> Estimated Time (ETA)
                            </label>
                            <div className="flex items-center gap-4">
                                <input type="range" min="3" max="30" step="1" value={etaMinutes} onChange={(e) => setEtaMinutes(parseInt(e.target.value))}
                                    className="flex-1 accent-brand-500" />
                                <span className="text-lg font-bold text-white w-12 text-center">{etaMinutes}m</span>
                            </div>
                        </div>

                        <div className="flex justify-end gap-3 pt-2">
                            <Button variant="ghost" onClick={() => setShowAssignModal(false)} className="rounded-2xl">Cancel</Button>
                            <Button onClick={handleAssignDriver} disabled={assigning} className="rounded-2xl shadow-lg shadow-brand-500/20 px-6">
                                {assigning ? <LoadingSpinner size="sm" /> : (<><Send className="h-4 w-4 mr-2" /> Assign Task</>)}
                            </Button>
                        </div>
                    </div>
                )}
            </Modal>
        </div>
    );
};

export default ActiveCars;
