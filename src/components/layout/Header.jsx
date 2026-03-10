import { useState, useRef, useEffect } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { useTheme } from '../../contexts/ThemeContext';
import { useNavigate } from 'react-router-dom';
import { Menu, Bell, LogOut, User, Shield, Mail, Building2, ChevronDown, Sun, Moon } from 'lucide-react';

const Header = ({ onMobileMenu }) => {
    const { profile, role, signOut, user, companyName } = useAuth();
    const { isDark, toggleTheme } = useTheme();
    const navigate = useNavigate();
    const [showProfile, setShowProfile] = useState(false);
    const dropdownRef = useRef(null);

    useEffect(() => {
        const handleClick = (e) => {
            if (dropdownRef.current && !dropdownRef.current.contains(e.target)) setShowProfile(false);
        };
        document.addEventListener('mousedown', handleClick);
        return () => document.removeEventListener('mousedown', handleClick);
    }, []);

    const handleSignOut = async () => {
        await signOut();
        navigate('/login', { replace: true });
    };

    const roleConfig = {
        admin: { label: 'Admin', color: 'text-red-400', bg: 'bg-red-500/10' },
        company: { label: 'Company', color: 'text-blue-400', bg: 'bg-blue-500/10' },
        valet: { label: 'Valet', color: 'text-brand-400', bg: 'bg-brand-500/10' },
    };

    const currentRole = roleConfig[role] || roleConfig.valet;

    return (
        <header className={`sticky top-0 z-40 flex h-16 shrink-0 items-center gap-x-4 border-b backdrop-blur-xl px-6 transition-colors duration-300 ${isDark ? 'border-white/5 bg-dark-900/80' : 'border-gray-200 bg-white/80'}`}>
            <button type="button" className={`md:hidden transition-colors ${isDark ? 'text-gray-400 hover:text-white' : 'text-gray-500 hover:text-gray-900'}`} onClick={onMobileMenu}>
                <Menu className="h-6 w-6" />
            </button>
            <div className="flex flex-1 items-center justify-between">
                <div className="hidden md:block" />
                <div className="flex items-center gap-4 ml-auto">
                    {/* Theme Toggle */}
                    <button
                        onClick={toggleTheme}
                        className={`p-2 rounded-xl transition-colors ${isDark ? 'text-gray-400 hover:text-white hover:bg-white/5' : 'text-gray-500 hover:text-gray-900 hover:bg-gray-100'}`}
                        title={isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode'}
                    >
                        {isDark ? <Sun className="h-5 w-5" /> : <Moon className="h-5 w-5" />}
                    </button>

                    <button className={`relative p-2 rounded-xl transition-colors ${isDark ? 'text-gray-400 hover:text-white hover:bg-white/5' : 'text-gray-500 hover:text-gray-900 hover:bg-gray-100'}`}>
                        <Bell className="h-5 w-5" />
                        <span className="absolute top-1.5 right-1.5 h-2 w-2 bg-brand-500 rounded-full" />
                    </button>

                    {/* User Profile Button */}
                    <div className="relative" ref={dropdownRef}>
                        <button
                            onClick={() => setShowProfile(!showProfile)}
                            className={`flex items-center gap-3 pl-4 border-l rounded-xl px-3 py-1.5 transition-all ${isDark ? 'border-white/5 hover:bg-white/5' : 'border-gray-200 hover:bg-gray-100'}`}
                        >
                            <div className="h-8 w-8 rounded-full bg-gradient-to-br from-brand-400 to-brand-600 flex items-center justify-center text-white text-sm font-bold shadow-lg shadow-brand-500/20">
                                {profile?.name?.charAt(0)?.toUpperCase() || 'U'}
                            </div>
                            <div className="hidden sm:block text-left">
                                <p className={`text-sm font-medium ${isDark ? 'text-white' : 'text-gray-900'}`}>{profile?.name || 'User'}</p>
                                <p className={`text-xs capitalize ${currentRole.color}`}>{currentRole.label}</p>
                            </div>
                            <ChevronDown className={`h-4 w-4 text-gray-500 transition-transform ${showProfile ? 'rotate-180' : ''}`} />
                        </button>

                        {/* Dropdown */}
                        {showProfile && (
                            <div className={`absolute right-0 top-full mt-2 w-72 border rounded-2xl shadow-2xl overflow-hidden animate-fade-in z-50 ${isDark ? 'bg-dark-800 border-white/10 shadow-black/50' : 'bg-white border-gray-200 shadow-gray-200/50'}`}>
                                {/* Profile Header */}
                                <div className={`p-4 bg-gradient-to-r from-brand-500/5 to-transparent border-b ${isDark ? 'border-white/5' : 'border-gray-100'}`}>
                                    <div className="flex items-center gap-3">
                                        <div className="h-12 w-12 rounded-full bg-gradient-to-br from-brand-400 to-brand-600 flex items-center justify-center text-white text-lg font-bold shadow-lg shadow-brand-500/20">
                                            {profile?.name?.charAt(0)?.toUpperCase() || 'U'}
                                        </div>
                                        <div>
                                            <p className={`text-sm font-semibold ${isDark ? 'text-white' : 'text-gray-900'}`}>{profile?.name || 'User'}</p>
                                            <span className={`inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full ${currentRole.color} ${currentRole.bg} mt-0.5`}>
                                                <Shield className="h-3 w-3" />
                                                {currentRole.label}
                                            </span>
                                        </div>
                                    </div>
                                </div>

                                {/* Profile Details */}
                                <div className="p-3 space-y-1">
                                    <div className={`flex items-center gap-3 px-3 py-2.5 rounded-xl ${isDark ? 'text-gray-400' : 'text-gray-600'}`}>
                                        <Mail className="h-4 w-4 text-gray-500 shrink-0" />
                                        <div>
                                            <p className={`text-[10px] uppercase tracking-wider ${isDark ? 'text-gray-600' : 'text-gray-400'}`}>Email</p>
                                            <p className={`text-xs break-all ${isDark ? 'text-gray-300' : 'text-gray-700'}`}>{profile?.email || user?.email || '—'}</p>
                                        </div>
                                    </div>

                                    {profile?.phone && (
                                        <div className={`flex items-center gap-3 px-3 py-2.5 rounded-xl ${isDark ? 'text-gray-400' : 'text-gray-600'}`}>
                                            <User className="h-4 w-4 text-gray-500 shrink-0" />
                                            <div>
                                                <p className={`text-[10px] uppercase tracking-wider ${isDark ? 'text-gray-600' : 'text-gray-400'}`}>Phone</p>
                                                <p className={`text-xs ${isDark ? 'text-gray-300' : 'text-gray-700'}`}>{profile.phone}</p>
                                            </div>
                                        </div>
                                    )}

                                    <div className={`flex items-center gap-3 px-3 py-2.5 rounded-xl ${isDark ? 'text-gray-400' : 'text-gray-600'}`}>
                                        <Building2 className="h-4 w-4 text-gray-500 shrink-0" />
                                        <div>
                                            <p className={`text-[10px] uppercase tracking-wider ${isDark ? 'text-gray-600' : 'text-gray-400'}`}>Company</p>
                                            <p className={`text-xs ${isDark ? 'text-gray-300' : 'text-gray-700'}`}>{companyName}</p>
                                        </div>
                                    </div>

                                    <div className={`flex items-center gap-3 px-3 py-2.5 rounded-xl ${isDark ? 'text-gray-400' : 'text-gray-600'}`}>
                                        <User className="h-4 w-4 text-gray-500 shrink-0" />
                                        <div>
                                            <p className={`text-[10px] uppercase tracking-wider ${isDark ? 'text-gray-600' : 'text-gray-400'}`}>User ID</p>
                                            <p className={`text-xs font-mono ${isDark ? 'text-gray-300' : 'text-gray-700'}`}>{profile?.id?.slice(0, 8)}...</p>
                                        </div>
                                    </div>
                                </div>

                                {/* Sign Out */}
                                <div className={`border-t p-2 ${isDark ? 'border-white/5' : 'border-gray-100'}`}>
                                    <button
                                        onClick={handleSignOut}
                                        className={`w-full flex items-center gap-3 px-3 py-2.5 text-sm rounded-xl transition-all duration-200 ${isDark ? 'text-red-400 hover:bg-red-500/10' : 'text-red-500 hover:bg-red-50'}`}
                                    >
                                        <LogOut className="h-4 w-4" />
                                        Sign Out
                                    </button>
                                </div>
                            </div>
                        )}
                    </div>
                </div>
            </div>
        </header>
    );
};

export default Header;
