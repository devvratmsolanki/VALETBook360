import { useState, useEffect } from 'react';
import { getDriverPerformanceStats } from '../../services/transactionService';
import { useAuth } from '../../contexts/AuthContext';
import Card from '../../components/ui/Card';
import { toast } from '../../components/ui/Toast';
import { BarChart3, UserCheck, MapPin, TrendingUp, Clock, Car } from 'lucide-react';

const DriverPerformance = () => {
    const { companyId } = useAuth();
    const [transactions, setTransactions] = useState([]);
    const [loading, setLoading] = useState(true);
    const [activeTab, setActiveTab] = useState('drivers');

    useEffect(() => {
        const fetchData = async () => {
            try {
                setTransactions(await getDriverPerformanceStats(companyId));
            } catch (err) {
                toast.error('Failed to load analytics');
            } finally {
                setLoading(false);
            }
        };
        fetchData();
    }, [companyId]);

    // Build per-driver stats
    const getDriverStats = () => {
        const driverMap = {};
        transactions.forEach((tx) => {
            // Parked by
            if (tx.parked_driver) {
                const id = tx.parked_by_driver_id;
                if (!driverMap[id]) driverMap[id] = { id, name: tx.parked_driver.name, staff_id: tx.parked_driver.staff_id, parkCount: 0, retrieveCount: 0, totalTrips: 0, avgEta: [] };
                driverMap[id].parkCount++;
                driverMap[id].totalTrips++;
            }
            // Retrieved by
            if (tx.retrieved_driver) {
                const id = tx.retrieved_by_driver_id;
                if (!driverMap[id]) driverMap[id] = { id, name: tx.retrieved_driver.name, staff_id: tx.retrieved_driver.staff_id, parkCount: 0, retrieveCount: 0, totalTrips: 0, avgEta: [] };
                driverMap[id].retrieveCount++;
                driverMap[id].totalTrips++;
                if (tx.eta_minutes) driverMap[id].avgEta.push(tx.eta_minutes);
            }
        });
        return Object.values(driverMap)
            .map(d => ({
                ...d,
                avgEtaMin: d.avgEta.length > 0 ? Math.round(d.avgEta.reduce((a, b) => a + b, 0) / d.avgEta.length) : null,
            }))
            .sort((a, b) => b.totalTrips - a.totalTrips);
    };

    // Build per-location stats
    const getLocationStats = () => {
        const locMap = {};
        transactions.forEach((tx) => {
            if (!tx.locations) return;
            const id = tx.locations.id;
            if (!locMap[id]) locMap[id] = { id, name: tx.locations.name, total: 0, active: 0, delivered: 0, parked: 0 };
            locMap[id].total++;
            if (['parked', 'requested', 'ready'].includes(tx.status)) locMap[id].active++;
            if (tx.status === 'delivered') locMap[id].delivered++;
            if (tx.status === 'parked') locMap[id].parked++;
        });
        return Object.values(locMap).sort((a, b) => b.total - a.total);
    };

    const driverStats = getDriverStats();
    const locationStats = getLocationStats();

    if (loading) return <div className="flex items-center justify-center h-64"><div className="animate-spin h-8 w-8 border-2 border-brand-500 border-t-transparent rounded-full" /></div>;

    return (
        <div className="animate-fade-in">
            <div className="mb-6">
                <h1 className="text-2xl font-bold text-white">Analytics</h1>
                <p className="text-sm text-gray-500 mt-1">Driver performance & location insights</p>
            </div>

            {/* Tab Switcher */}
            <div className="flex gap-2 mb-6">
                <button onClick={() => setActiveTab('drivers')}
                    className={`px-4 py-2.5 rounded-xl text-sm font-medium flex items-center gap-2 transition-all ${activeTab === 'drivers' ? 'bg-brand-500/10 text-brand-400 border border-brand-500/20' : 'text-gray-500 hover:text-white hover:bg-white/5 border border-transparent'}`}>
                    <UserCheck className="h-4 w-4" /> Driver Performance
                </button>
                <button onClick={() => setActiveTab('locations')}
                    className={`px-4 py-2.5 rounded-xl text-sm font-medium flex items-center gap-2 transition-all ${activeTab === 'locations' ? 'bg-brand-500/10 text-brand-400 border border-brand-500/20' : 'text-gray-500 hover:text-white hover:bg-white/5 border border-transparent'}`}>
                    <MapPin className="h-4 w-4" /> Location Analytics
                </button>
            </div>

            {/* Driver Performance Tab */}
            {activeTab === 'drivers' && (
                <div>
                    {driverStats.length === 0 ? (
                        <Card className="p-8 text-center"><UserCheck className="h-8 w-8 text-gray-600 mx-auto mb-3" /><p className="text-gray-500">No driver data yet. Assign drivers during check-in to see analytics.</p></Card>
                    ) : (
                        <div className="space-y-4">
                            {/* Summary Row */}
                            <div className="grid grid-cols-3 gap-3">
                                <Card className="p-4 text-center"><p className="text-2xl font-bold text-brand-400">{driverStats.length}</p><p className="text-xs text-gray-500 mt-1">Active Drivers</p></Card>
                                <Card className="p-4 text-center"><p className="text-2xl font-bold text-emerald-400">{driverStats.reduce((sum, d) => sum + d.totalTrips, 0)}</p><p className="text-xs text-gray-500 mt-1">Total Trips</p></Card>
                                <Card className="p-4 text-center"><p className="text-2xl font-bold text-blue-400">{transactions.length}</p><p className="text-xs text-gray-500 mt-1">Total Transactions</p></Card>
                            </div>

                            {/* Driver Cards */}
                            <Card className="overflow-hidden">
                                <div className="overflow-x-auto">
                                    <table className="w-full text-left text-sm">
                                        <thead className="bg-dark-700/50 text-xs uppercase text-gray-500">
                                            <tr>
                                                <th className="px-6 py-3">Driver</th>
                                                <th className="px-6 py-3 text-center">Cars Parked</th>
                                                <th className="px-6 py-3 text-center">Cars Retrieved</th>
                                                <th className="px-6 py-3 text-center">Total Trips</th>
                                                <th className="px-6 py-3 text-center">Avg ETA</th>
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-white/5">
                                            {driverStats.map((d, i) => (
                                                <tr key={d.id} className="hover:bg-white/[0.02] transition-colors">
                                                    <td className="px-6 py-4">
                                                        <div className="flex items-center gap-3">
                                                            <div className={`h-8 w-8 rounded-full flex items-center justify-center text-xs font-bold ${i === 0 ? 'bg-brand-500/20 text-brand-400' : 'bg-dark-600 text-gray-400'}`}>
                                                                {i === 0 ? '🏆' : i + 1}
                                                            </div>
                                                            <div>
                                                                <p className="font-medium text-white text-sm">{d.name}</p>
                                                                <p className="text-[10px] text-brand-500/80 uppercase font-semibold">{d.staff_id || 'No ID'}</p>
                                                            </div>
                                                        </div>
                                                    </td>
                                                    <td className="px-6 py-4 text-center">
                                                        <span className="text-blue-400 font-semibold">{d.parkCount}</span>
                                                    </td>
                                                    <td className="px-6 py-4 text-center">
                                                        <span className="text-emerald-400 font-semibold">{d.retrieveCount}</span>
                                                    </td>
                                                    <td className="px-6 py-4 text-center">
                                                        <span className="text-white font-bold">{d.totalTrips}</span>
                                                    </td>
                                                    <td className="px-6 py-4 text-center">
                                                        {d.avgEtaMin ? (
                                                            <span className="text-amber-400 flex items-center justify-center gap-1"><Clock className="h-3 w-3" />{d.avgEtaMin} min</span>
                                                        ) : <span className="text-gray-600">—</span>}
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            </Card>
                        </div>
                    )}
                </div>
            )}

            {/* Location Analytics Tab */}
            {activeTab === 'locations' && (
                <div>
                    {locationStats.length === 0 ? (
                        <Card className="p-8 text-center"><MapPin className="h-8 w-8 text-gray-600 mx-auto mb-3" /><p className="text-gray-500">No location data yet. Assign locations during check-in to see analytics.</p></Card>
                    ) : (
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                            {locationStats.map((loc) => (
                                <Card key={loc.id} className="p-5">
                                    <div className="flex items-start gap-3 mb-4">
                                        <div className="bg-brand-500/10 p-2 rounded-xl"><MapPin className="h-5 w-5 text-brand-400" /></div>
                                        <div>
                                            <p className="font-medium text-white">{loc.name}</p>
                                            <p className="text-xs text-gray-500">{loc.total} total transactions</p>
                                        </div>
                                    </div>
                                    <div className="grid grid-cols-3 gap-3">
                                        <div className="bg-dark-600 rounded-lg p-3 text-center">
                                            <p className="text-lg font-bold text-brand-400">{loc.active}</p>
                                            <p className="text-[10px] text-gray-500 uppercase">Active</p>
                                        </div>
                                        <div className="bg-dark-600 rounded-lg p-3 text-center">
                                            <p className="text-lg font-bold text-blue-400">{loc.parked}</p>
                                            <p className="text-[10px] text-gray-500 uppercase">Parked</p>
                                        </div>
                                        <div className="bg-dark-600 rounded-lg p-3 text-center">
                                            <p className="text-lg font-bold text-emerald-400">{loc.delivered}</p>
                                            <p className="text-[10px] text-gray-500 uppercase">Delivered</p>
                                        </div>
                                    </div>
                                </Card>
                            ))}
                        </div>
                    )}
                </div>
            )}
        </div>
    );
};

export default DriverPerformance;
