import { useState, useEffect, useMemo, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { Bell, Car, CheckCircle, Clock, Navigation, Key } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { parseUTC } from '../../lib/utils';

// Visible-status whitelist + presentation per transaction status.
const STATUS_META = {
    waiting_for_driver: { label: 'New car waiting', icon: Clock, color: 'text-orange-400', bg: 'bg-orange-500/10' },
    parked: { label: 'Car parked', icon: Car, color: 'text-brand-400', bg: 'bg-brand-500/10' },
    key_in: { label: 'Key handed in', icon: Key, color: 'text-amber-400', bg: 'bg-amber-500/10' },
    requested: { label: 'Retrieval requested', icon: Clock, color: 'text-amber-400', bg: 'bg-amber-500/10' },
    driver_assigned: { label: 'Driver assigned', icon: Navigation, color: 'text-purple-400', bg: 'bg-purple-500/10' },
    en_route: { label: 'Driver en route', icon: Navigation, color: 'text-blue-400', bg: 'bg-blue-500/10' },
    arrived: { label: 'Car ready', icon: CheckCircle, color: 'text-emerald-400', bg: 'bg-emerald-500/10' },
    delivered: { label: 'Car delivered', icon: CheckCircle, color: 'text-gray-400', bg: 'bg-gray-500/10' },
    cancelled: { label: 'Cancelled', icon: Clock, color: 'text-red-400', bg: 'bg-red-500/10' },
};

const formatRelative = (ts) => {
    const d = parseUTC(ts);
    if (!d) return '';
    const diff = Date.now() - d.getTime();
    const m = Math.floor(diff / 60000);
    if (m < 1) return 'just now';
    if (m < 60) return `${m}m ago`;
    const h = Math.floor(m / 60);
    if (h < 24) return `${h}h ago`;
    return `${Math.floor(h / 24)}d ago`;
};

const readSeen = (userId) => {
    if (!userId) return '9999-01-01T00:00:00Z';
    try { return localStorage.getItem(`notif_seen_${userId}`) || '1970-01-01T00:00:00Z'; }
    catch { return '1970-01-01T00:00:00Z'; }
};

const NotificationsBell = () => {
    const { user, role, companyId, locationId } = useAuth();
    const navigate = useNavigate();
    const [open, setOpen] = useState(false);
    const [items, setItems] = useState([]);
    // Key the cursor by the actual user id so two operators sharing a browser
    // don't inherit each other's "read" state. Initializer reads synchronously
    // for the current user.id, then we re-derive whenever it changes.
    const [lastSeen, setLastSeen] = useState(() => readSeen(user?.id));
    const lastUserIdRef = useRef(user?.id);
    if (lastUserIdRef.current !== user?.id) {
        lastUserIdRef.current = user?.id;
        const fresh = readSeen(user?.id);
        if (fresh !== lastSeen) setLastSeen(fresh);
    }
    const wrapRef = useRef(null);

    const scopeKey = useMemo(() => `${role}:${companyId || ''}:${locationId || ''}`, [role, companyId, locationId]);

    // Fetch + subscribe. Combined into one effect so we don't have a useCallback that
    // triggers cascading renders. Drivers see notifications in their task list instead,
    // so we skip the load/subscribe entirely for them.
    useEffect(() => {
        if (!user || role === 'driver') return;

        let cancelled = false;
        const buildQuery = () => {
            let q = supabase
                .from('valet_transactions')
                .select(`id, status, created_at, updated_at, valet_company_id, location_id,
                         cars(car_number, make, model),
                         locations:location_id(name)`)
                .order('updated_at', { ascending: false })
                .limit(20);
            if (role === 'company' && companyId) q = q.eq('valet_company_id', companyId);
            if (role === 'valet') {
                if (companyId) q = q.eq('valet_company_id', companyId);
                if (locationId) q = q.eq('location_id', locationId);
            }
            return q;
        };

        const load = async () => {
            const { data, error } = await buildQuery();
            if (cancelled) return;
            if (error) { console.error('[Notifications]', error); return; }
            setItems(data || []);
        };

        load();

        const channel = supabase
            .channel(`notif-${scopeKey}`)
            .on('postgres_changes', { event: '*', schema: 'public', table: 'valet_transactions' }, load)
            .subscribe();

        return () => {
            cancelled = true;
            channel.unsubscribe();
        };
    }, [user, role, companyId, locationId, scopeKey]);

    // Close on outside click
    useEffect(() => {
        const onClick = (e) => {
            if (wrapRef.current && !wrapRef.current.contains(e.target)) setOpen(false);
        };
        if (open) document.addEventListener('mousedown', onClick);
        return () => document.removeEventListener('mousedown', onClick);
    }, [open]);

    const unreadCount = useMemo(() => {
        const cutoff = parseUTC(lastSeen)?.getTime() ?? 0;
        return items.filter(i => {
            const ts = parseUTC(i.updated_at || i.created_at);
            return ts && ts.getTime() > cutoff;
        }).length;
    }, [items, lastSeen]);

    const markAllRead = () => {
        if (!user?.id) return;
        const now = new Date().toISOString();
        setLastSeen(now);
        try { localStorage.setItem(`notif_seen_${user.id}`, now); } catch { /* ignore quota errors */ }
    };

    const handleOpen = () => {
        setOpen((o) => {
            const next = !o;
            if (next) markAllRead();
            return next;
        });
    };

    const handleClickItem = () => {
        setOpen(false);
        const target = role === 'admin' ? '/admin/transactions'
            : role === 'company' ? '/company/transactions'
                : role === 'valet' ? '/operator'
                    : '/driver';
        navigate(target);
    };

    return (
        <div className="relative" ref={wrapRef}>
            <button
                onClick={handleOpen}
                className="relative p-2 rounded-xl transition-colors text-gray-400 hover:text-white hover:bg-white/5"
                aria-label={`Notifications${unreadCount ? ` (${unreadCount} unread)` : ''}`}
            >
                <Bell className="h-5 w-5" />
                {unreadCount > 0 && (
                    <span className="absolute -top-0.5 -right-0.5 min-w-[18px] h-[18px] px-1 bg-brand-500 text-white text-[10px] font-bold rounded-full flex items-center justify-center shadow shadow-brand-500/40">
                        {unreadCount > 9 ? '9+' : unreadCount}
                    </span>
                )}
            </button>

            {open && (
                <div className="absolute right-0 top-full mt-2 w-96 bg-dark-800 border border-white/10 rounded-2xl shadow-2xl shadow-black/50 z-50 overflow-hidden animate-fade-in">
                    <div className="px-4 py-3 border-b border-white/5 flex items-center justify-between">
                        <div>
                            <p className="text-sm font-semibold text-white">Notifications</p>
                            <p className="text-[11px] text-gray-500">
                                {role === 'admin' ? 'All companies'
                                    : role === 'company' ? 'Your company'
                                        : role === 'valet' ? 'Your location'
                                            : 'Your tasks'}
                            </p>
                        </div>
                        {items.length > 0 && (
                            <button onClick={handleClickItem} className="text-[11px] text-brand-400 hover:text-brand-300">View all →</button>
                        )}
                    </div>

                    <div className="max-h-96 overflow-y-auto">
                        {items.length === 0 ? (
                            <div className="px-4 py-8 text-center">
                                <Bell className="h-7 w-7 text-gray-700 mx-auto mb-2" />
                                <p className="text-xs text-gray-500">
                                    {role === 'driver' ? 'Driver notifications appear in your task list' : 'No recent activity'}
                                </p>
                            </div>
                        ) : (
                            <ul className="divide-y divide-white/5">
                                {items.map((t) => {
                                    const meta = STATUS_META[t.status] || STATUS_META.parked;
                                    const Icon = meta.icon;
                                    return (
                                        <li
                                            key={t.id}
                                            onClick={handleClickItem}
                                            className="px-4 py-3 hover:bg-white/[0.02] cursor-pointer flex items-start gap-3"
                                        >
                                            <div className={`${meta.bg} p-1.5 rounded-lg shrink-0`}>
                                                <Icon className={`h-3.5 w-3.5 ${meta.color}`} />
                                            </div>
                                            <div className="flex-1 min-w-0">
                                                <p className="text-sm text-white truncate">
                                                    <span className={`${meta.color} font-medium`}>{meta.label}</span>
                                                    {t.cars?.car_number && <span className="text-gray-400"> · {t.cars.car_number}</span>}
                                                </p>
                                                <p className="text-[11px] text-gray-500 mt-0.5 truncate">
                                                    {t.locations?.name || 'Unknown location'} · {formatRelative(t.updated_at || t.created_at)}
                                                </p>
                                            </div>
                                        </li>
                                    );
                                })}
                            </ul>
                        )}
                    </div>
                </div>
            )}
        </div>
    );
};

export default NotificationsBell;
