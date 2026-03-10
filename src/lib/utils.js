import { clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs) {
    return twMerge(clsx(inputs));
}

// Supabase returns UTC timestamps sometimes without 'Z' suffix,
// causing JS to interpret them as local time. This ensures correct parsing.
export function parseUTC(dateString) {
    if (!dateString) return null;
    // If no timezone indicator present, append 'Z' to treat as UTC
    if (!dateString.endsWith('Z') && !dateString.includes('+') && !/\d{2}:\d{2}$/.test(dateString.slice(-6))) {
        return new Date(dateString + 'Z');
    }
    return new Date(dateString);
}

export function formatTime(dateString) {
    const d = parseUTC(dateString);
    return d ? d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '—';
}

export function formatDate(dateString) {
    const d = parseUTC(dateString);
    return d ? d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : '—';
}

export function formatDateTime(dateString) {
    return `${formatDate(dateString)} ${formatTime(dateString)}`;
}

export function getStatusColor(status) {
    const colors = {
        parked: 'bg-brand-500/10 text-brand-400 border-brand-500/20',
        requested: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
        ready: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
        delivered: 'bg-gray-500/10 text-gray-400 border-gray-500/20',
        cancelled: 'bg-red-500/10 text-red-400 border-red-500/20',
    };
    return colors[status] || colors.parked;
}
