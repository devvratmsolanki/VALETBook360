import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import { useTheme } from '../../contexts/ThemeContext';
import { cn } from '../../lib/utils';
import {
    LayoutDashboard, PlusCircle, Car, Users, Building2,
    FileText, MapPin, MessageSquare, ClipboardList, LogOut, Shield, BarChart3
} from 'lucide-react';

const operatorNav = [
    { name: 'Dashboard', href: '/operator', icon: LayoutDashboard },
];

const companyNav = [
    { name: 'Dashboard', href: '/company', icon: LayoutDashboard },
    { name: 'Transactions', href: '/company/transactions', icon: ClipboardList },
    { name: 'Drivers', href: '/company/drivers', icon: Users },
    { name: 'Locations', href: '/company/locations', icon: MapPin },
    { name: 'Team', href: '/company/staff', icon: Users },
    { name: 'Contracts', href: '/company/contracts', icon: FileText },
    { name: 'Analytics', href: '/company/analytics', icon: BarChart3 },
];

const adminNav = [
    { name: 'Dashboard', href: '/admin', icon: LayoutDashboard },
    { name: 'Companies', href: '/admin/companies', icon: Building2 },
    { name: 'Users', href: '/admin/users', icon: Users },
    { name: 'Transactions', href: '/admin/transactions', icon: ClipboardList },
    { name: 'WhatsApp Logs', href: '/admin/logs', icon: MessageSquare },
];

const Sidebar = () => {
    const location = useLocation();
    const { role, signOut, companyName } = useAuth();
    const { isDark } = useTheme();

    const getNavItems = () => {
        switch (role) {
            case 'admin': return adminNav;
            case 'company': return companyNav;
            default: return operatorNav;
        }
    };

    const getRoleBadge = () => {
        switch (role) {
            case 'admin': return { label: 'Admin', color: 'text-red-400' };
            case 'company': return { label: 'Company', color: 'text-blue-400' };
            case 'valet': return { label: 'Valet', color: 'text-brand-400' };
            default: return { label: 'Valet', color: 'text-brand-400' };
        }
    };

    const badge = getRoleBadge();
    const navigation = getNavItems();

    return (
        <div className={cn(
            'hidden border-r md:fixed md:inset-y-0 md:flex md:w-64 md:flex-col transition-colors duration-300',
            isDark ? 'bg-dark-950 border-white/5' : 'bg-white border-gray-200'
        )}>
            <div className="flex grow flex-col gap-y-5 overflow-y-auto px-5 pb-4">
                <div className={cn(
                    'flex h-16 shrink-0 items-center border-b -mx-5 px-5',
                    isDark ? 'border-white/5' : 'border-gray-200'
                )}>
                    <div className="flex items-center gap-2.5">
                        <div className="bg-brand-500 p-1.5 rounded-lg">
                            <Car className="h-5 w-5 text-white" />
                        </div>
                        <div>
                            <span className="font-serif text-lg font-bold text-brand-500">{companyName || 'VALETBook360'}</span>
                            <p className={cn('text-[10px] uppercase tracking-widest -mt-0.5', isDark ? 'text-gray-600' : 'text-gray-400')}>Premium Service</p>
                        </div>
                    </div>
                </div>

                <div className="px-2 py-1">
                    <div className="flex items-center gap-2">
                        <Shield className={cn('h-3.5 w-3.5', badge.color)} />
                        <span className={cn('text-xs font-medium', badge.color)}>{badge.label}</span>
                    </div>
                    {companyName && <p className={cn('text-[11px] mt-0.5 ml-5', isDark ? 'text-gray-500' : 'text-gray-500')}>{companyName}</p>}
                </div>

                <nav className="flex flex-1 flex-col">
                    <ul role="list" className="flex flex-1 flex-col gap-y-1">
                        {navigation.map((item) => {
                            const isActive = location.pathname === item.href || (item.href !== '/' && location.pathname.startsWith(item.href + '/'));
                            return (
                                <li key={item.name}>
                                    <Link
                                        to={item.href}
                                        className={cn(
                                            'group flex gap-x-3 rounded-xl p-2.5 text-sm font-medium border transition-all duration-200',
                                            isActive
                                                ? 'bg-brand-500/10 text-brand-400 border-brand-500/20'
                                                : isDark
                                                    ? 'text-gray-400 hover:text-white hover:bg-white/5 border-transparent'
                                                    : 'text-gray-600 hover:text-gray-900 hover:bg-gray-100 border-transparent'
                                        )}
                                    >
                                        <item.icon className={cn('h-5 w-5 shrink-0', isActive && 'text-brand-500')} />
                                        {item.name}
                                    </Link>
                                </li>
                            );
                        })}
                    </ul>
                </nav>

                <button
                    onClick={signOut}
                    className={cn(
                        'flex items-center gap-3 px-2.5 py-2.5 text-sm font-medium rounded-xl transition-all duration-200 border',
                        isDark
                            ? 'text-gray-500 hover:text-red-400 hover:bg-red-500/5 border-transparent hover:border-red-500/10'
                            : 'text-gray-500 hover:text-red-500 hover:bg-red-50 border-transparent hover:border-red-200'
                    )}
                >
                    <LogOut className="h-5 w-5" /> Sign Out
                </button>
                <p className={cn('text-center text-[10px] mt-2', isDark ? 'text-gray-700' : 'text-gray-400')}>
                    {companyName || 'VALETBook360'} — Premium Valet Platform
                </p>
            </div>
        </div>
    );
};

export default Sidebar;
