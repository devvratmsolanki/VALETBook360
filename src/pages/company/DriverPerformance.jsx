import { useState, useEffect } from 'react';
import { getDriverPerformanceStats } from '../../services/transactionService';
import { useAuth } from '../../contexts/AuthContext';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
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
                if (companyId) {
                    setTransactions(await getDriverPerformanceStats(companyId));
                }
            } catch (err) {
                toast.error('Failed to load analytics');
            } finally {
                setLoading(false);
            }
        };
        fetchData();
    }, [companyId]);

    const getDriverStats = () => {
        const driverMap = {};
        transactions.forEach((tx) => {
            if (tx.parked_driver) {
                const id = tx.parked_by_driver_id;
                if (!driverMap[id]) driverMap[id] = { id, name: tx.parked_driver.name, staff_id: tx.parked_driver.staff_id, parkCount: 0, retrieveCount: 0, totalTrips: 0, avgEta: [] };
                driverMap[id].parkCount++;
                driverMap[id].totalTrips++;
            }
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

    if (loading) return <div className="flex items-center justify-center h-64"><LoadingSpinner size="lg" /></div>;

    return (
        <div className="animate-fade-in">
            <div className="mb-6">
                <h1 className="text-2xl font-bold text-white">Analytics</h1>
                <p className="text-sm text-gray-500 mt-1">Driver performance & location insights</p>
            </div>

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

            {activeTab === 'drivers' && (
                <div>
                    {driverStats.length === 0 ? (
                        <Card className="p-8 text-center"><UserCheck className="h-8 w-8 text-gray-600 mx-auto mb-3" /><p className="text-gray-500">No driver data yet. Assign drivers during check-in to see analytics.</p></Card>
                    ) : (
                        <div className="space-y-4">
                            <div className="grid grid-cols-3 gap-3">
                                <Card className="p-4 bg-brand-500/5 border-brand-500/10">
                                    <p className="text-[10px] uppercase tracking-wider text-gray-500 font-semibold">Total Trips</p>
                                    <p className="text-xl font-bold text-white mt-1">{transactions.length}</p>
                                </Card>
                                <Card className="p-4 bg-emerald-500/5 border-emerald-500/10">
                                    <p className="text-[10px] uppercase tracking-wider text-gray-500 font-semibold">Active Drivers</p>
                                    <p className="text-xl font-bold text-white mt-1">{driverStats.length}</p>
                                </Card>
                                <Card className="p-4 bg-blue-500/5 border-blue-500/10">
                                    <p className="text-[10px] uppercase tracking-wider text-gray-500 font-semibold">Avg ETA</p>
                                    <p className="text-xl font-bold text-white mt-1">~6m</p>
                                </Card>
                            </div>

                            <Card className="overflow-hidden">
                                <div className="overflow-x-auto">
                                    <table className="w-full text-left text-sm">
                                        <thead className="bg-dark-700/50 text-xs uppercase text-gray-500">
                                            <tr>
                                                <th className="px-6 py-3 text-center">Rank</th>
                                                <th className="px-6 py-3">Driver</th>
                                                <th className="px-6 py-3 text-center">Parking</th>
                                                <th className="px-6 py-3 text-center">Retrieval</th>
                                                <th className="px-6 py-3 text-center">Avg ETA</th>
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-white/5">
                                            {driverStats.map((d, i) => (
                                                <tr key={d.id} className="hover:bg-white/[0.02] transition-colors">
                                                    <td className="px-6 py-4 text-center">
                                                        <span className={`inline-flex items-center justify-center h-6 w-6 rounded-lg text-[10px] font-bold ${i === 0 ? 'bg-yellow-500/20 text-yellow-500' : 'bg-gray-500/10 text-gray-500'}`}>{i + 1}</span>
                                                    </td>
                                                    <td className="px-6 py-4">
                                                        <div className="flex items-center gap-3">
                                                            <div className="h-8 w-8 rounded-full bg-dark-600 flex items-center justify-center text-xs font-bold text-brand-400">
                                                                {d.name?.charAt(0)}
                                                            </div>
                                                            <div>
                                                                <p className="font-medium text-white">{d.name}</p>
                                                                <p className="text-[10px] text-gray-500 uppercase">{d.staff_id || 'VT-00'}</p>
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
                                                        {d.avgEtaMin ? (
                                                            <span className="text-gray-300 font-medium">{d.avgEtaMin}m</span>
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

            {activeTab === 'locations' && (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {locationStats.length === 0 ? (
                        <Card className="p-8 text-center col-span-2"><MapPin className="h-8 w-8 text-gray-600 mx-auto mb-3" /><p className="text-gray-500">No location data available yet.</p></Card>
                    ) : locationStats.map(loc => (
                        <Card key={loc.id} className="p-5">
                            <div className="flex items-center justify-between mb-4">
                                <div className="flex items-center gap-3">
                                    <div className="bg-brand-500/10 p-2 rounded-xl"><MapPin className="h-5 w-5 text-brand-400" /></div>
                                    <p className="font-bold text-white">{loc.name}</p>
                                </div>
                                <div className="text-right">
                                    <p className="text-2xl font-bold text-white">{loc.total}</p>
                                    <p className="text-[10px] text-gray-500 uppercase">Total Visits</p>
                                </div>
                            </div>
                            <div className="grid grid-cols-3 gap-2">
                                <div className="bg-dark-600/50 p-2 rounded-lg text-center">
                                    <p className="text-brand-400 font-bold">{loc.parked}</p>
                                    <p className="text-[8px] text-gray-600 uppercase">Parked</p>
                                </div>
                                <div className="bg-dark-600/50 p-2 rounded-lg text-center">
                                    <p className="text-emerald-400 font-bold">{loc.delivered}</p>
                                    <p className="text-[8px] text-gray-600 uppercase">Delivered</p>
                                </div>
                                <div className="bg-dark-600/50 p-2 rounded-lg text-center">
                                    <p className="text-amber-400 font-bold">{loc.active}</p>
                                    <p className="text-[8px] text-gray-600 uppercase">Active</p>
                                </div>
                            </div>
                        </Card>
                    ))}
                </div>
            )}
        </div>
    );
};

export default DriverPerformance;
