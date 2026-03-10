import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { getTransactionStats } from '../../services/transactionService';
import Card from '../../components/ui/Card';
import { Car, Building2, Users, Activity, TrendingUp, Clock, CheckCircle, ArrowRight } from 'lucide-react';

const AdminDashboard = () => {
    const navigate = useNavigate();
    const [stats, setStats] = useState({ total: 0, active: 0, parked: 0, requested: 0, ready: 0, delivered: 0, today: 0 });
    const [loading, setLoading] = useState(true);

    useEffect(() => { getTransactionStats().then(setStats).catch(console.error).finally(() => setLoading(false)); }, []);

    const statCards = [
        { label: 'Total Transactions', value: stats.total, icon: Activity, color: 'text-blue-400', bg: 'bg-blue-500/10', href: '/admin/transactions' },
        { label: 'Active Vehicles', value: stats.active, icon: Car, color: 'text-brand-400', bg: 'bg-brand-500/10', href: '/admin/transactions?status=parked' },
        { label: "Today's Check-ins", value: stats.today, icon: TrendingUp, color: 'text-emerald-400', bg: 'bg-emerald-500/10', href: '/admin/transactions' },
        { label: 'Parked', value: stats.parked, icon: Car, color: 'text-indigo-400', bg: 'bg-indigo-500/10', href: '/admin/transactions?status=parked' },
        { label: 'Requested', value: stats.requested, icon: Clock, color: 'text-amber-400', bg: 'bg-amber-500/10', href: '/admin/transactions?status=requested' },
        { label: 'Delivered', value: stats.delivered, icon: CheckCircle, color: 'text-gray-400', bg: 'bg-gray-500/10', href: '/admin/transactions?status=delivered' },
    ];

    const quickLinks = [
        { label: 'Companies', icon: Building2, href: '/admin/companies', color: 'text-purple-400', bg: 'bg-purple-500/10' },
        { label: 'Users', icon: Users, href: '/admin/users', color: 'text-cyan-400', bg: 'bg-cyan-500/10' },
    ];

    if (loading) return <div className="flex items-center justify-center h-64"><div className="animate-spin h-8 w-8 border-2 border-brand-500 border-t-transparent rounded-full" /></div>;

    return (
        <div className="animate-fade-in">
            <div className="mb-8"><h1 className="text-2xl font-bold text-white">Admin Dashboard</h1><p className="text-sm text-gray-500 mt-1">System-wide overview</p></div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 mb-6">{statCards.map((s) => (<Card key={s.label} className="p-5 cursor-pointer hover:border-brand-500/20 hover:bg-white/[0.02] transition-all group" onClick={() => navigate(s.href)}><div className="flex items-center justify-between"><div><p className="text-sm text-gray-400">{s.label}</p><p className="text-3xl font-bold text-white mt-1">{s.value}</p></div><div className={`${s.bg} p-3 rounded-xl group-hover:scale-110 transition-transform`}><s.icon className={`h-6 w-6 ${s.color}`} /></div></div><div className="flex items-center gap-1 mt-3 text-xs text-gray-600 group-hover:text-brand-400 transition-colors"><span>View details</span><ArrowRight className="h-3 w-3" /></div></Card>))}</div>
            <h3 className="text-sm font-semibold text-gray-400 uppercase tracking-wider mb-3">Quick Links</h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">{quickLinks.map(l => (<Card key={l.label} className="p-5 cursor-pointer hover:border-brand-500/20 hover:bg-white/[0.02] transition-all group" onClick={() => navigate(l.href)}><div className="flex items-center gap-4"><div className={`${l.bg} p-3 rounded-xl group-hover:scale-110 transition-transform`}><l.icon className={`h-6 w-6 ${l.color}`} /></div><div className="flex-1"><p className="text-white font-medium">{l.label}</p><p className="text-xs text-gray-500">Manage {l.label.toLowerCase()}</p></div><ArrowRight className="h-4 w-4 text-gray-600 group-hover:text-brand-400 transition-colors" /></div></Card>))}</div>
        </div>
    );
};

export default AdminDashboard;

