import { useState, useEffect, useCallback, useRef } from 'react';
import { CheckCircle, XCircle, AlertCircle, Info, X } from 'lucide-react';
import { cn } from '../../lib/utils';

const icons = { success: CheckCircle, error: XCircle, warning: AlertCircle, info: Info };
const styles = {
    success: 'bg-emerald-500/10 border-emerald-500/20 text-emerald-400',
    error: 'bg-red-500/10 border-red-500/20 text-red-400',
    warning: 'bg-amber-500/10 border-amber-500/20 text-amber-400',
    info: 'bg-blue-500/10 border-blue-500/20 text-blue-400',
};

// At most this many visible toasts at once. Anything beyond gets dropped so a
// flood of realtime events (e.g. status updates on many transactions) can't
// stack up and obscure the UI.
const MAX_VISIBLE = 4;
// Identical (type+message) toasts within this window collapse onto the
// existing toast by bumping its count rather than spawning a new one. Most
// realtime spam (`Status updated`) ends up looking like "Status updated ×4".
const DEDUP_WINDOW_MS = 2500;

let addToast;

const ToastItem = ({ toast, onRemove }) => {
    const Icon = icons[toast.type];
    useEffect(() => {
        const timer = setTimeout(() => onRemove(toast.id), 4000);
        return () => clearTimeout(timer);
    }, [toast.id, toast.count, onRemove]);

    return (
        <div className={cn('flex items-center gap-3 p-4 rounded-xl border shadow-lg animate-slide-up', styles[toast.type])}>
            <Icon className="h-5 w-5 shrink-0" />
            <p className="text-sm flex-1">{toast.message}{toast.count > 1 ? ` ×${toast.count}` : ''}</p>
            <button onClick={() => onRemove(toast.id)} className="shrink-0 hover:opacity-70"><X className="h-4 w-4" /></button>
        </div>
    );
};

export const ToastContainer = () => {
    const [toasts, setToasts] = useState([]);
    const counterRef = useRef(0);
    const remove = useCallback((id) => { setToasts((prev) => prev.filter((t) => t.id !== id)); }, []);
    useEffect(() => {
        addToast = (message, type = 'success') => {
            const now = Date.now();
            setToasts((prev) => {
                const recent = prev.find((t) => t.type === type && t.message === message && (now - t.createdAt) < DEDUP_WINDOW_MS);
                if (recent) {
                    return prev.map((t) => t === recent ? { ...t, count: (t.count || 1) + 1, createdAt: now } : t);
                }
                const id = `t-${++counterRef.current}`;
                const next = [...prev, { id, message, type, count: 1, createdAt: now }];
                // Keep most recent N — drop oldest if overflowing.
                return next.length > MAX_VISIBLE ? next.slice(next.length - MAX_VISIBLE) : next;
            });
        };
    }, []);

    return (
        <div className="fixed top-4 right-4 left-4 sm:left-auto z-[100] flex flex-col gap-2 sm:w-full sm:max-w-sm">
            {toasts.map((t) => (<ToastItem key={t.id} toast={t} onRemove={remove} />))}
        </div>
    );
};

export const toast = {
    success: (msg) => addToast?.(msg, 'success'),
    error: (msg) => addToast?.(msg, 'error'),
    warning: (msg) => addToast?.(msg, 'warning'),
    info: (msg) => addToast?.(msg, 'info'),
};
