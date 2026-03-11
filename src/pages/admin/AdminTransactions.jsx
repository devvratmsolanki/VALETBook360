import { useState, useEffect } from 'react';
import { getTransactions, getTransactionStats } from '../../services/transactionService';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import Card from '../../components/ui/Card';
import Badge from '../../components/ui/Badge';
import { toast } from '../../components/ui/Toast';
import { Search, Filter, Download, Car, Calendar, Clock, MapPin, User, ArrowRight } from 'lucide-react';
import { formatTime, parseUTC } from '../../lib/utils';

const AdminTransactions = () => {
    const [transactions, setTransactions] = useState([]);
    const [filtered, setFiltered] = useState([]);
    const [stats, setStats] = useState({ total: 0, active: 0, delivered: 0 });
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');
    const [statusFilter, setStatusFilter] = useState('all');

    const fetchData = async () => {
        try {
            const [data, s] = await Promise.all([
                getTransactions(),
                getTransactionStats()
            ]);
            setTransactions(data);
            setFiltered(data);
            setStats(s);
        } catch {
            toast.error('Failed to load transactions');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => { fetchData(); }, []);

    useEffect(() => {
        let result = transactions;
        if (search) {
            const s = search.toLowerCase();
            result = result.filter(t =>
                t.visitors?.name?.toLowerCase().includes(s) ||
                t.cars?.car_number?.toLowerCase().includes(s) ||
                t.visitors?.phone?.toLowerCase().includes(s)
            );
        }
        if (statusFilter !== 'all') {
            result = result.filter(t => t.status === statusFilter);
        }
        setFiltered(result);
    }, [search, statusFilter, transactions]);

    const statusStyles = {
        parked: 'bg-brand-500/10 text-brand-400 border-brand-500/20',
        requested: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
        ready: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
        delivered: 'bg-gray-500/10 text-gray-500 border-gray-500/20',
    };

    if (loading) return <div className="flex items-center justify-center h-64"><LoadingSpinner size="lg" /></div>;

    return (
        <div className="animate-fade-in">
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-6">
                <div>
                    <h1 className="text-2xl font-bold text-white">Transactions</h1>
                    <p className="text-sm text-gray-500 mt-1">{stats.total} total transactions across system</p>
                </div>
                <div className="flex items-center gap-2">
                    <button onClick={fetchData} className="p-2.5 rounded-xl bg-dark-600 border border-white/5 text-gray-400 hover:text-white transition-all">
                        <Download className="h-4 w-4" />
                    </button>
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
                <Card className="p-4 bg-brand-500/5 border-brand-500/10">
                    <div className="flex items-center gap-3">
                        <div className="bg-brand-500/10 p-2 rounded-lg"><Activity className="h-4 w-4 text-brand-400" /></div>
                        <div><p className="text-[10px] uppercase text-gray-500 font-semibold">Total</p><p className="text-xl font-bold text-white">{stats.total}</p></div>
                    </div>
                </Card>
                <Card className="p-4 bg-emerald-500/5 border-emerald-500/10">
                    <div className="flex items-center gap-3">
                        <div className="bg-emerald-500/10 p-2 rounded-lg"><Car className="h-4 w-4 text-emerald-400" /></div>
                        <div><p className="text-[10px] uppercase text-gray-500 font-semibold">Active</p><p className="text-xl font-bold text-white">{stats.active}</p></div>
                    </div>
                </Card>
                <Card className="p-4 bg-amber-500/5 border-amber-500/10">
                    <div className="flex items-center gap-3">
                        <div className="bg-amber-500/10 p-2 rounded-lg"><Clock className="h-4 w-4 text-amber-400" /></div>
                        <div><p className="text-[10px] uppercase text-gray-500 font-semibold">Requested</p><p className="text-xl font-bold text-white">{stats.requested || 0}</p></div>
                    </div>
                </Card>
                <Card className="p-4 bg-gray-500/5 border-gray-500/10">
                    <div className="flex items-center gap-3">
                        <div className="bg-gray-500/10 p-2 rounded-lg"><CheckCircle className="h-4 w-4 text-gray-500" /></div>
                        <div><p className="text-[10px] uppercase text-gray-500 font-semibold">Delivered</p><p className="text-xl font-bold text-white">{stats.delivered}</p></div>
                    </div>
                </Card>
            </div>

            <div className="flex flex-col md:flex-row gap-3 mb-6">
                <div className="relative flex-1">
                    <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500" />
                    <input
                        type="text"
                        value={search}
                        onChange={(e) => setSearch(e.target.value)}
                        placeholder="Search by name, car number, or phone..."
                        className="block w-full rounded-xl border-0 bg-dark-600 py-2.5 pl-10 pr-4 text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all"
                    />
                </div>
                <div className="flex items-center gap-2">
                    <Filter className="h-4 w-4 text-gray-500 ml-2" />
                    <select
                        value={statusFilter}
                        onChange={(e) => setStatusFilter(e.target.value)}
                        className="bg-dark-600 border-0 ring-1 ring-white/5 rounded-xl text-sm text-gray-300 py-2.5 pl-3 pr-8 focus:ring-2 focus:ring-brand-500/50"
                    >
                        <option value="all">All Status</option>
                        <option value="parked">Parked</option>
                        <option value="requested">Requested</option>
                        <option value="ready">Ready</option>
                        <option value="delivered">Delivered</option>
                    </select>
                </div>
            </div>

            <Card className="overflow-hidden">
                <div className="overflow-x-auto">
                    <table className="w-full text-left text-sm">
                        <thead className="bg-dark-700/50 text-xs uppercase text-gray-500">
                            <tr>
                                <th className="px-6 py-3">Vehicle</th>
                                <th className="px-6 py-3">Guest</th>
                                <th className="px-6 py-3">Location</th>
                                <th className="px-6 py-3">Status</th>
                                <th className="px-6 py-3 text-right">Time</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-white/5">
                            {filtered.length === 0 ? (
                                <tr><td colSpan="5" className="px-6 py-12 text-center text-gray-500">No transactions found matching filters</td></tr>
                            ) : filtered.map((t) => (
                                <tr key={t.id} className="hover:bg-white/[0.02] transition-colors group">
                                    <td className="px-6 py-4">
                                        <div className="flex items-center gap-3">
                                            <div className="bg-brand-500/10 p-2 rounded-lg group-hover:scale-110 transition-transform"><Car className="h-4 w-4 text-brand-400" /></div>
                                            <div>
                                                <p className="font-bold text-white uppercase">{t.cars?.car_number}</p>
                                                <p className="text-[10px] text-gray-500 uppercase">{t.cars?.make} {t.cars?.model}</p>
                                            </div>
                                        </div>
                                    </td>
                                    <td className="px-6 py-4">
                                        <div className="flex items-center gap-2"><User className="h-3.5 w-3.5 text-gray-600" /><p className="font-medium text-gray-300">{t.visitors?.name}</p></div>
                                        <p className="text-[10px] text-gray-600 ml-5">{t.visitors?.phone}</p>
                                    </td>
                                    <td className="px-6 py-4">
                                        <div className="flex items-center gap-2 text-gray-400"><MapPin className="h-3.5 w-3.5" />{t.locations?.name || 'N/A'}</div>
                                    </td>
                                    <td className="px-6 py-4"><Badge className={statusStyles[t.status] || ''}>{t.status}</Badge></td>
                                    <td className="px-6 py-4 text-right">
                                        <div className="flex flex-col items-end">
                                            <div className="flex items-center gap-1 text-gray-300 text-xs font-mono"><Clock className="h-3 w-3 text-gray-600" /> {formatTime(parseUTC(t.created_at))}</div>
                                            <p className="text-[10px] text-gray-600 mt-0.5">{new Date(t.created_at).toLocaleDateString()}</p>
                                        </div>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            </Card>
        </div>
    );
};

export default AdminTransactions;

import { Activity, CheckCircle } from 'lucide-react';
