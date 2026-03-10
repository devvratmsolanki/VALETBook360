import { useState, useEffect, useCallback } from 'react';
import { CheckCircle, XCircle, AlertCircle, Info, X } from 'lucide-react';
import { cn } from '../../lib/utils';

const icons = { success: CheckCircle, error: XCircle, warning: AlertCircle, info: Info };
const styles = {
    success: 'bg-emerald-500/10 border-emerald-500/20 text-emerald-400',
    error: 'bg-red-500/10 border-red-500/20 text-red-400',
    warning: 'bg-amber-500/10 border-amber-500/20 text-amber-400',
    info: 'bg-blue-500/10 border-blue-500/20 text-blue-400',
};

let addToast;

const ToastItem = ({ toast, onRemove }) => {
    const Icon = icons[toast.type];
    useEffect(() => {
        const timer = setTimeout(() => onRemove(toast.id), 4000);
        return () => clearTimeout(timer);
    }, [toast.id, onRemove]);

    return (
        <div className={cn('flex items-center gap-3 p-4 rounded-xl border shadow-lg animate-slide-up', styles[toast.type])}>
            <Icon className="h-5 w-5 shrink-0" />
            <p className="text-sm flex-1">{toast.message}</p>
            <button onClick={() => onRemove(toast.id)} className="shrink-0 hover:opacity-70"><X className="h-4 w-4" /></button>
        </div>
    );
};

export const ToastContainer = () => {
    const [toasts, setToasts] = useState([]);
    const remove = useCallback((id) => { setToasts((prev) => prev.filter((t) => t.id !== id)); }, []);
    useEffect(() => {
        addToast = (message, type = 'success') => {
            const id = Date.now();
            setToasts((prev) => [...prev, { id, message, type }]);
        };
    }, []);

    return (
        <div className="fixed top-4 right-4 z-[100] flex flex-col gap-2 w-80">
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
