import { clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs) {
    return twMerge(clsx(inputs));
}

// Supabase returns UTC timestamps sometimes without 'Z' suffix,
// causing JS to interpret them as local time. This ensures correct parsing.
// Detects explicit TZ markers (Z, ±HH:MM, ±HHMM) and only appends Z when none is present.
const TZ_SUFFIX_RE = /(Z|[+-]\d{2}:?\d{2})$/;
export function parseUTC(dateString) {
    if (!dateString) return null;
    const s = String(dateString);
    if (TZ_SUFFIX_RE.test(s)) return new Date(s);
    return new Date(s + 'Z');
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

// ─── Validation ───
// Trims, then matches a standard email pattern. Empty string treated as invalid.
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
export function isValidEmail(value) {
    return EMAIL_RE.test((value || '').trim());
}

// Accepts numbers with optional leading +, separators are ignored.
// Requires 7–15 digits (E.164-ish range).
export function normalizePhone(value) {
    return (value || '').replace(/\D/g, '');
}
export function isValidPhone(value) {
    const digits = normalizePhone(value);
    return digits.length >= 7 && digits.length <= 15;
}

// Minimum-strength password: ≥8 chars, contains a letter and a digit.
export function isValidPassword(value) {
    if (!value || value.length < 8) return false;
    return /[A-Za-z]/.test(value) && /\d/.test(value);
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
