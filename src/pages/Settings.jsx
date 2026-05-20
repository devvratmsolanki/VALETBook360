import { useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../contexts/AuthContext';
import { isValidPassword } from '../lib/utils';
import Card from '../components/ui/Card';
import Button from '../components/ui/Button';
import { toast } from '../components/ui/Toast';
import { Key, Eye, EyeOff, Mail, Shield, Building2 } from 'lucide-react';

const Settings = () => {
    const { user, role, companyName } = useAuth();
    const [current, setCurrent] = useState('');
    const [next, setNext] = useState('');
    const [confirm, setConfirm] = useState('');
    const [showCurrent, setShowCurrent] = useState(false);
    const [showNext, setShowNext] = useState(false);
    const [saving, setSaving] = useState(false);

    const handleSubmit = async (e) => {
        e.preventDefault();
        if (!current) return toast.error('Enter your current password');
        if (!isValidPassword(next)) return toast.error('New password needs 8+ chars with a letter and a number');
        if (next !== confirm) return toast.error('New passwords do not match');
        if (next === current) return toast.error('New password must differ from current');

        setSaving(true);
        try {
            // Re-authenticate to confirm the current password before changing it.
            const { error: authErr } = await supabase.auth.signInWithPassword({ email: user.email, password: current });
            if (authErr) {
                toast.error('Current password is incorrect');
                return;
            }
            const { error } = await supabase.auth.updateUser({ password: next });
            if (error) throw error;
            toast.success('Password updated');
            setCurrent(''); setNext(''); setConfirm('');
        } catch (err) {
            toast.error(err.message || 'Failed to update password');
        } finally {
            setSaving(false);
        }
    };

    const roleLabel = { admin: 'Super Admin', company: 'Company Owner', valet: 'Operator', driver: 'Driver' }[role] || role;

    return (
        <div className="animate-fade-in max-w-2xl">
            <div className="mb-6">
                <h1 className="text-2xl font-bold text-white">Account Settings</h1>
                <p className="text-sm text-gray-500 mt-1">Manage your sign-in credentials</p>
            </div>

            <Card className="p-5 mb-4">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
                    <div className="flex items-center gap-3">
                        <Mail className="h-4 w-4 text-gray-500" />
                        <div>
                            <p className="text-xs text-gray-500 uppercase tracking-wider">Email</p>
                            <p className="text-gray-200">{user?.email}</p>
                        </div>
                    </div>
                    <div className="flex items-center gap-3">
                        <Shield className="h-4 w-4 text-gray-500" />
                        <div>
                            <p className="text-xs text-gray-500 uppercase tracking-wider">Role</p>
                            <p className="text-gray-200">{roleLabel}</p>
                        </div>
                    </div>
                    {companyName && (
                        <div className="flex items-center gap-3 sm:col-span-2">
                            <Building2 className="h-4 w-4 text-gray-500" />
                            <div>
                                <p className="text-xs text-gray-500 uppercase tracking-wider">Company</p>
                                <p className="text-gray-200">{companyName}</p>
                            </div>
                        </div>
                    )}
                </div>
            </Card>

            <Card className="p-5">
                <h2 className="text-lg font-semibold text-white mb-1">Change Password</h2>
                <p className="text-xs text-gray-500 mb-5">You'll stay signed in after changing it.</p>

                <form onSubmit={handleSubmit} className="space-y-4">
                    <PasswordField
                        label="Current Password"
                        value={current}
                        onChange={setCurrent}
                        show={showCurrent}
                        onToggle={() => setShowCurrent(s => !s)}
                        autoComplete="current-password"
                    />
                    <PasswordField
                        label="New Password"
                        value={next}
                        onChange={setNext}
                        show={showNext}
                        onToggle={() => setShowNext(s => !s)}
                        autoComplete="new-password"
                        hint="Min 8 chars with at least one letter and one number"
                    />
                    <PasswordField
                        label="Confirm New Password"
                        value={confirm}
                        onChange={setConfirm}
                        show={showNext}
                        onToggle={() => setShowNext(s => !s)}
                        autoComplete="new-password"
                    />
                    <div className="flex justify-end pt-2">
                        <Button type="submit" disabled={saving}>{saving ? 'Updating...' : 'Update Password'}</Button>
                    </div>
                </form>
            </Card>
        </div>
    );
};

const PasswordField = ({ label, value, onChange, show, onToggle, autoComplete, hint }) => (
    <div className="space-y-1.5">
        <label className="block text-sm font-medium text-gray-300">{label}</label>
        <div className="relative group">
            <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3.5">
                <Key className="h-4 w-4 text-gray-500 group-focus-within:text-brand-500 transition-colors" />
            </div>
            <input
                type={show ? 'text' : 'password'}
                value={value}
                onChange={(e) => onChange(e.target.value)}
                autoComplete={autoComplete}
                required
                className="block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-10 text-gray-200 placeholder:text-gray-500 ring-1 ring-inset ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all"
            />
            <button type="button" onClick={onToggle} className="absolute inset-y-0 right-0 flex items-center pr-3 text-gray-500 hover:text-gray-300">
                {show ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
            </button>
        </div>
        {hint && <p className="text-[11px] text-gray-500">{hint}</p>}
    </div>
);

export default Settings;
