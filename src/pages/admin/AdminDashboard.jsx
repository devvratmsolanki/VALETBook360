import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { getTransactionStats, getActiveTransactions, subscribeToTransactions } from '../../services/transactionService';
import { getCompanies } from '../../services/companyService';
import { getLocations } from '../../services/locationService';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import Card from '../../components/ui/Card';
import { Car, Building2, Users, Activity, TrendingUp, Clock, CheckCircle, ArrowRight, MapPin } from 'lucide-react';
import logger from '../../lib/logger';

const AdminDashboard = () => {
    const navigate = useNavigate();
    const [stats, setStats] = useState({ total: 0, active: 0, parked: 0, requested: 0, ready: 0, delivered: 0, today: 0 });
    const [companies, setCompanies] = useState([]); // {id, name, owner, active, locations}
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        let cancelled = false;
        const load = async () => {
            try {
                const [s, comps, locs] = await Promise.all([
                    getTransactionStats(),
                    getCompanies(),
                    getLocations(),
                ]);
                // Locations per company (single fetch, grouped client-side).
                const locByCompany = {};
                for (const l of locs) {
                    locByCompany[l.valet_company_id] = (locByCompany[l.valet_company_id] || 0) + 1;
                }
                // Active cars per company (scoped fetches — the unscoped call is
                // refused by the service to avoid cross-tenant leaks).
                const actives = await Promise.all(
                    comps.map((c) => getActiveTransactions(c.id).catch(() => [])),
                );
                if (cancelled) return;
                setStats(s);
                setCompanies(
                    comps
                        .map((c, i) => ({
                            id: c.id,
                            name: c.company_name,
                            owner: c.owner_name || c.email || '—',
                            active: actives[i].length,
                            locations: locByCompany[c.id] || 0,
                        }))
                        .sort((a, b) => b.active - a.active),
                );
            } catch (err) {
                logger.error(err);
            } finally {
                if (!cancelled) setLoading(false);
            }
        };
        load();
        const sub = subscribeToTransactions(() => load());
        return () => { cancelled = true; sub.unsubscribe(); };
    }, []);

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
        { label: 'Locations', icon: MapPin, href: '/admin/locations', color: 'text-brand-400', bg: 'bg-brand-500/10' },
        { label: 'Users', icon: Users, href: '/admin/users', color: 'text-cyan-400', bg: 'bg-cyan-500/10' },
    ];

    const go = (href) => (e) => {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); navigate(href); }
    };

    if (loading) return <div className="flex items-center justify-center h-64"><LoadingSpinner size="lg" /></div>;

    return (
        <div className="animate-fade-in">
            <div className="mb-8"><h1 className="text-2xl font-bold text-white">Admin Dashboard</h1><p className="text-sm text-gray-500 mt-1">System-wide overview · live</p></div>

            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">{statCards.map((s) => (<Card key={s.label} role="button" tabIndex={0} aria-label={s.label} onKeyDown={go(s.href)} className="p-5 cursor-pointer hover:border-brand-500/20 hover:bg-white/[0.02] transition-all group" onClick={() => navigate(s.href)}><div className="flex items-center justify-between"><div><p className="text-sm text-gray-400">{s.label}</p><p className="text-3xl font-bold text-white mt-1">{s.value}</p></div><div className={`${s.bg} p-3 rounded-xl group-hover:scale-110 transition-transform`}><s.icon className={`h-6 w-6 ${s.color}`} /></div></div><div className="flex items-center gap-1 mt-3 text-xs text-gray-600 group-hover:text-brand-400 transition-colors"><span>View details</span><ArrowRight className="h-3 w-3" /></div></Card>))}</div>

            {/* Live per-company breakdown — the company→location→operator→driver drill-down entry point */}
            <div className="flex items-center justify-between mb-3">
                <h3 className="text-sm font-semibold text-gray-400 uppercase tracking-wider">Companies <span className="text-gray-600 normal-case font-normal">· {companies.length}</span></h3>
                <button type="button" onClick={() => navigate('/admin/companies')} className="text-xs text-brand-400 hover:text-brand-300 flex items-center gap-1">All companies <ArrowRight className="h-3 w-3" /></button>
            </div>
            {companies.length === 0 ? (
                <Card className="p-8 text-center mb-8"><Building2 className="h-8 w-8 text-gray-600 mx-auto mb-2" /><p className="text-gray-500 text-sm">No companies yet</p></Card>
            ) : (
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
                    {companies.map((c) => (
                        <Card key={c.id} role="button" tabIndex={0} aria-label={`Open ${c.name}`} onKeyDown={go(`/admin/companies/${c.id}`)} onClick={() => navigate(`/admin/companies/${c.id}`)} className="p-5 cursor-pointer hover:border-brand-500/20 hover:bg-white/[0.02] transition-all group">
                            <div className="flex items-start justify-between gap-3">
                                <div className="min-w-0">
                                    <p className="text-white font-semibold truncate">{c.name}</p>
                                    <p className="text-xs text-gray-500 truncate">{c.owner}</p>
                                </div>
                                {c.active > 0 && (
                                    <span className="shrink-0 inline-flex items-center gap-1 rounded-full bg-brand-500/10 border border-brand-500/20 px-2 py-0.5 text-[11px] font-semibold text-brand-300">
                                        <span className="h-1.5 w-1.5 rounded-full bg-brand-400 animate-pulse" />{c.active} active
                                    </span>
                                )}
                            </div>
                            <div className="flex items-center gap-4 mt-4 text-xs text-gray-400">
                                <span className="flex items-center gap-1"><Car className="h-3.5 w-3.5 text-brand-400" /> {c.active} active</span>
                                <span className="flex items-center gap-1"><MapPin className="h-3.5 w-3.5 text-gray-500" /> {c.locations} location{c.locations === 1 ? '' : 's'}</span>
                                <ArrowRight className="h-3.5 w-3.5 ml-auto text-gray-600 group-hover:text-brand-400 transition-colors" />
                            </div>
                        </Card>
                    ))}
                </div>
            )}

            <h3 className="text-sm font-semibold text-gray-400 uppercase tracking-wider mb-3">Quick Links</h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">{quickLinks.map(l => (<Card key={l.label} role="button" tabIndex={0} aria-label={l.label} onKeyDown={go(l.href)} className="p-5 cursor-pointer hover:border-brand-500/20 hover:bg-white/[0.02] transition-all group" onClick={() => navigate(l.href)}><div className="flex items-center gap-4"><div className={`${l.bg} p-3 rounded-xl group-hover:scale-110 transition-transform`}><l.icon className={`h-6 w-6 ${l.color}`} /></div><div className="flex-1"><p className="text-white font-medium">{l.label}</p><p className="text-xs text-gray-500">Manage {l.label.toLowerCase()}</p></div><ArrowRight className="h-4 w-4 text-gray-600 group-hover:text-brand-400 transition-colors" /></div></Card>))}</div>
        </div>
    );
};

export default AdminDashboard;
