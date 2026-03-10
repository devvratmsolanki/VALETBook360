import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { Car, Mail, Lock, Eye, EyeOff } from 'lucide-react';
import { cn } from '../lib/utils';

const Login = () => {
    const navigate = useNavigate();
    const { signIn, user, loading: authLoading } = useAuth();
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [showPassword, setShowPassword] = useState(false);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);

    // Redirect if already logged in
    useEffect(() => {
        if (!authLoading && user) {
            navigate('/', { replace: true });
        }
    }, [user, authLoading, navigate]);

    const handleSubmit = async (e) => {
        e.preventDefault();
        setLoading(true);
        setError(null);
        try {
            await signIn(email, password);
            // Navigate after successful sign-in
            navigate('/', { replace: true });
        } catch (err) {
            setError(err.message || 'Invalid credentials');
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="min-h-screen bg-dark-900 flex items-center justify-center p-4">
            <div className="fixed inset-0 overflow-hidden pointer-events-none">
                <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-brand-500/5 rounded-full blur-3xl" />
                <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-brand-500/3 rounded-full blur-3xl" />
            </div>
            <div className="relative w-full max-w-md animate-fade-in">
                <div className="flex flex-col items-center mb-8">
                    <div className="bg-brand-500 p-3 rounded-2xl shadow-lg shadow-brand-500/20 mb-4">
                        <Car className="h-8 w-8 text-black" />
                    </div>
                    <h1 className="font-serif text-3xl font-bold text-brand-500">VALETBook360</h1>
                    <p className="text-xs text-gray-500 uppercase tracking-[0.3em] mt-1">Premium Valet Service</p>
                </div>

                <div className="glass-card p-8 relative overflow-hidden">
                    <div className="absolute top-0 left-0 w-full h-px bg-gradient-to-r from-transparent via-brand-500/30 to-transparent" />
                    <h2 className="text-xl font-semibold text-white mb-1">Welcome back</h2>
                    <p className="text-sm text-gray-500 mb-6">Sign in to your account</p>

                    <form onSubmit={handleSubmit} className="space-y-4">
                        {error && <div className="bg-red-500/10 border border-red-500/20 text-red-400 p-3 rounded-xl text-sm">{error}</div>}
                        <div className="space-y-1.5">
                            <label className="text-sm font-medium text-gray-300">Email</label>
                            <div className="relative group">
                                <Mail className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500 group-focus-within:text-brand-500 transition-colors" />
                                <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="Enter your email" required className="block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-4 text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all" />
                            </div>
                        </div>
                        <div className="space-y-1.5">
                            <label className="text-sm font-medium text-gray-300">Password</label>
                            <div className="relative group">
                                <Lock className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500 group-focus-within:text-brand-500 transition-colors" />
                                <input type={showPassword ? 'text' : 'password'} value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Enter your password" required className="block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-12 text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all" />
                                <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-3.5 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-300">
                                    {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                                </button>
                            </div>
                        </div>
                        <button type="submit" disabled={loading} className={cn('w-full brand-gradient rounded-xl py-3 text-sm font-semibold text-black shadow-lg shadow-brand-900/20 hover:from-brand-300 hover:to-brand-500 transition-all duration-300 transform active:scale-[0.98] mt-2', loading && 'opacity-70 cursor-not-allowed')}>
                            {loading ? (<span className="flex items-center justify-center gap-2"><svg className="animate-spin h-4 w-4" viewBox="0 0 24 24"><circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" /><path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" /></svg>Signing in...</span>) : 'Sign In'}
                        </button>
                    </form>
                </div>
                <p className="text-center text-[11px] text-gray-600 mt-6">VALETBook360 — Premium Valet Management</p>
            </div>
        </div>
    );
};

export default Login;
