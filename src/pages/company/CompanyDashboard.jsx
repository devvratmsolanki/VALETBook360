import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import { getTransactionStats, getActiveTransactions, subscribeToTransactions, updateTransactionStatus } from '../../services/transactionService';
import Card from '../../components/ui/Card';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import { toast } from '../../components/ui/Toast';
import { formatTime } from '../../lib/utils';
import { Car, TrendingUp, Clock, Activity, ArrowRight } from 'lucide-react';

const CompanyDashboard = () => {
    const navigate = useNavigate();
    const { companyId } = useAuth();
    const [stats, setStats] = useState({ total: 0, active: 0, parked: 0, requested: 0, ready: 0, delivered: 0, today: 0 });
    const [recentTx, setRecentTx] = useState([]);
    const [loading, setLoading] = useState(true);

    const fetchData = async () => { try { const [s, a] = await Promise.all([getTransactionStats(companyId), getActiveTransactions(companyId)]); setStats(s); setRecentTx(a.slice(0, 5)); } catch (err) { console.error(err); } finally { setLoading(false); } };

    useEffect(() => { fetchData(); const sub = subscribeToTransactions(() => fetchData()); return () => sub.unsubscribe(); }, []);

    const handleStatusUpdate = async (id, status) => { try { await updateTransactionStatus(id, status); toast.success(`Updated to ${status}`); fetchData(); } catch { toast.error('Update failed'); } };

    const statCards = [
        { label: 'Active Cars', value: stats.active, icon: Car, color: 'text-brand-400', bg: 'bg-brand-500/10', href: '/company/transactions?status=parked' },
        { label: "Today's Check-ins", value: stats.today, icon: TrendingUp, color: 'text-emerald-400', bg: 'bg-emerald-500/10', href: '/company/transactions' },
        { label: 'Requested', value: stats.requested, icon: Clock, color: 'text-amber-400', bg: 'bg-amber-500/10', href: '/company/transactions?status=requested' },
        { label: 'Total Transactions', value: stats.total, icon: Activity, color: 'text-blue-400', bg: 'bg-blue-500/10', href: '/company/transactions' },
    ];

    if (loading) return <div className="flex items-center justify-center h-64"><div className="animate-spin h-8 w-8 border-2 border-brand-500 border-t-transparent rounded-full" /></div>;

    return (
        <div className="animate-fade-in">
            <div className="mb-8"><h1 className="text-2xl font-bold text-white">Dashboard</h1><p className="text-sm text-gray-500 mt-1">Overview of your valet operations</p></div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">{statCards.map((s) => (<Card key={s.label} className="p-5 cursor-pointer hover:border-brand-500/20 hover:bg-white/[0.02] transition-all group" onClick={() => navigate(s.href)}><div className="flex items-center justify-between"><div><p className="text-sm text-gray-400">{s.label}</p><p className="text-3xl font-bold text-white mt-1">{s.value}</p></div><div className={`${s.bg} p-3 rounded-xl group-hover:scale-110 transition-transform`}><s.icon className={`h-6 w-6 ${s.color}`} /></div></div><div className="flex items-center gap-1 mt-3 text-xs text-gray-600 group-hover:text-brand-400 transition-colors"><span>View details</span><ArrowRight className="h-3 w-3" /></div></Card>))}</div>
            <Card className="overflow-hidden">
                <div className="flex items-center justify-between px-6 py-4 border-b border-white/5"><h3 className="font-semibold text-white">Active Vehicles</h3><Button variant="ghost" size="sm" onClick={() => navigate('/company/transactions')}>View All <ArrowRight className="h-3.5 w-3.5" /></Button></div>
                {recentTx.length === 0 ? <div className="p-8 text-center"><Car className="h-8 w-8 text-gray-600 mx-auto mb-2" /><p className="text-gray-500 text-sm">No active vehicles</p></div> : (
                    <div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="bg-dark-700/50 text-xs uppercase text-gray-500"><tr><th className="px-6 py-3">Vehicle</th><th className="px-6 py-3">Guest</th><th className="px-6 py-3">Status</th><th className="px-6 py-3">Time</th><th className="px-6 py-3">Actions</th></tr></thead><tbody className="divide-y divide-white/5">{recentTx.map((tx) => (<tr key={tx.id} className="hover:bg-white/[0.02] transition-colors"><td className="px-6 py-4 font-medium text-white">{tx.cars?.car_number || 'N/A'}</td><td className="px-6 py-4 text-gray-400">{tx.visitors?.name || 'Unknown'}</td><td className="px-6 py-4"><Badge variant={tx.status}>{tx.status}</Badge></td><td className="px-6 py-4 text-gray-500">{formatTime(tx.created_at)}</td><td className="px-6 py-4">{tx.status === 'parked' && <Button size="sm" variant="outline" onClick={() => handleStatusUpdate(tx.id, 'requested')}>Request</Button>}{tx.status === 'requested' && <Button size="sm" variant="outline" className="border-emerald-500/30 text-emerald-400" onClick={() => handleStatusUpdate(tx.id, 'ready')}>Ready</Button>}{tx.status === 'ready' && <Button size="sm" variant="ghost" onClick={() => handleStatusUpdate(tx.id, 'delivered')}>Delivered</Button>}</td></tr>))}</tbody></table></div>
                )}
            </Card>
        </div>
    );
};

export default CompanyDashboard;
