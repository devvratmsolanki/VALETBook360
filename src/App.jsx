import { lazy, Suspense } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import { ThemeProvider } from './contexts/ThemeContext';
import { ToastContainer } from './components/ui/Toast';
import ErrorBoundary from './components/ui/ErrorBoundary';
import Layout from './components/layout/Layout';
import Login from './pages/Login';
import OperatorDashboard from './pages/operator/OperatorDashboard';
import CompanyDashboard from './pages/company/CompanyDashboard';
import DriverPanel from './pages/driver/DriverPanel';
import { isMockClient } from './lib/supabase';

// Lazy-loaded routes — these are admin/company sub-pages and heavy analytics
// screens that valet/driver users never visit. Splitting them off the main
// bundle keeps the initial JS payload small for the high-traffic operator
// dashboard. The Suspense fallback below renders the same loading spinner
// used by ProtectedRoute so the transition looks consistent.
const Drivers = lazy(() => import('./pages/company/Drivers'));
const CompanyTransactions = lazy(() => import('./pages/company/CompanyTransactions'));
const Locations = lazy(() => import('./pages/company/Locations'));
const LocationDetail = lazy(() => import('./pages/company/LocationDetail'));
const Contracts = lazy(() => import('./pages/company/Contracts'));
const DriverPerformance = lazy(() => import('./pages/company/DriverPerformance'));
const Staff = lazy(() => import('./pages/company/Staff'));
const AdminDashboard = lazy(() => import('./pages/admin/AdminDashboard'));
const Companies = lazy(() => import('./pages/admin/Companies'));
const CompanyDetail = lazy(() => import('./pages/admin/CompanyDetail'));
const AdminLocations = lazy(() => import('./pages/admin/AdminLocations'));
const Users = lazy(() => import('./pages/admin/Users'));
const AdminTransactions = lazy(() => import('./pages/admin/AdminTransactions'));
const WhatsAppLogs = lazy(() => import('./pages/admin/WhatsAppLogs'));
const Settings = lazy(() => import('./pages/Settings'));

// Role mapping: database stores 'admin', 'company', 'valet', and 'driver'.
// The frontend uses the same labels everywhere — there is no rename layer.
// `admin` = super admin (full system access),
// `company` = company owner (multi-location view),
// `valet` = operator at a specific location,
// `driver` = on-the-ground driver who parks/retrieves cars.

const RouteSpinner = () => (
    <div className="min-h-screen bg-dark-900 flex items-center justify-center">
        <div className="animate-spin h-8 w-8 border-2 border-brand-500 border-t-transparent rounded-full" />
    </div>
);

const ProtectedRoute = ({ children, allowedRoles }) => {
    const { user, role, loading } = useAuth();
    if (loading) return <RouteSpinner />;
    if (!user) return <Navigate to="/login" replace />;
    if (allowedRoles && !allowedRoles.includes(role)) {
        if (role === 'admin') return <Navigate to="/admin" replace />;
        if (role === 'company') return <Navigate to="/company" replace />;
        if (role === 'driver') return <Navigate to="/driver" replace />;
        return <Navigate to="/operator" replace />;
    }
    return (
        <Layout>
            {/* Per-route boundary: a render error in one page falls back to a
                recoverable error UI inside Layout so the sidebar/header stay
                usable for navigating away. */}
            <ErrorBoundary level="route">
                <Suspense fallback={<RouteSpinner />}>{children}</Suspense>
            </ErrorBoundary>
        </Layout>
    );
};

const AuthGate = () => {
    const { user, role, loading } = useAuth();
    if (loading) return <RouteSpinner />;
    if (!user) return <Navigate to="/login" replace />;
    if (role === 'admin') return <Navigate to="/admin" replace />;
    if (role === 'company') return <Navigate to="/company" replace />;
    if (role === 'driver') return <Navigate to="/driver" replace />;
    return <Navigate to="/operator" replace />;
};

// Renders only when the build is missing Supabase credentials so end users
// don't silently see demo-mode data instead of a real outage.
const DemoModeBanner = () => (
    <div className="fixed top-0 left-0 right-0 z-[200] bg-amber-500 text-black text-center text-xs font-bold py-1.5 px-3 shadow-lg">
        DEMO MODE — Supabase credentials not configured. No data will load and sign-in will fail.
    </div>
);

function App() {
    return (
        <ErrorBoundary level="app">
            <BrowserRouter>
                <ThemeProvider>
                    <AuthProvider>
                        {isMockClient && <DemoModeBanner />}
                        <ToastContainer />
                        <Routes>
                            <Route path="/login" element={<Login />} />
                            <Route path="/" element={<AuthGate />} />

                            <Route path="/operator" element={<ProtectedRoute allowedRoles={['valet', 'company', 'admin']}><OperatorDashboard /></ProtectedRoute>} />
                            <Route path="/driver" element={<ProtectedRoute allowedRoles={['driver', 'valet', 'company', 'admin']}><DriverPanel /></ProtectedRoute>} />

                            <Route path="/company" element={<ProtectedRoute allowedRoles={['company', 'admin']}><CompanyDashboard /></ProtectedRoute>} />
                            <Route path="/company/drivers" element={<ProtectedRoute allowedRoles={['company', 'admin']}><Drivers /></ProtectedRoute>} />
                            <Route path="/company/transactions" element={<ProtectedRoute allowedRoles={['company', 'admin']}><CompanyTransactions /></ProtectedRoute>} />
                            <Route path="/company/locations" element={<ProtectedRoute allowedRoles={['company', 'admin']}><Locations /></ProtectedRoute>} />
                            <Route path="/company/locations/:locationId" element={<ProtectedRoute allowedRoles={['company', 'admin']}><LocationDetail /></ProtectedRoute>} />
                            <Route path="/company/staff" element={<ProtectedRoute allowedRoles={['company', 'admin']}><Staff /></ProtectedRoute>} />
                            <Route path="/company/contracts" element={<ProtectedRoute allowedRoles={['company', 'admin']}><Contracts /></ProtectedRoute>} />
                            <Route path="/company/analytics" element={<ProtectedRoute allowedRoles={['company', 'admin']}><DriverPerformance /></ProtectedRoute>} />

                            <Route path="/admin" element={<ProtectedRoute allowedRoles={['admin']}><AdminDashboard /></ProtectedRoute>} />
                            <Route path="/admin/companies" element={<ProtectedRoute allowedRoles={['admin']}><Companies /></ProtectedRoute>} />
                            <Route path="/admin/companies/:id" element={<ProtectedRoute allowedRoles={['admin']}><CompanyDetail /></ProtectedRoute>} />
                            <Route path="/admin/locations" element={<ProtectedRoute allowedRoles={['admin']}><AdminLocations /></ProtectedRoute>} />
                            <Route path="/admin/users" element={<ProtectedRoute allowedRoles={['admin']}><Users /></ProtectedRoute>} />
                            <Route path="/admin/transactions" element={<ProtectedRoute allowedRoles={['admin']}><AdminTransactions /></ProtectedRoute>} />
                            <Route path="/admin/logs" element={<ProtectedRoute allowedRoles={['admin']}><WhatsAppLogs /></ProtectedRoute>} />

                            <Route path="/settings" element={<ProtectedRoute allowedRoles={['admin', 'company', 'valet', 'driver']}><Settings /></ProtectedRoute>} />

                            <Route path="*" element={<Navigate to="/" replace />} />
                        </Routes>
                    </AuthProvider>
                </ThemeProvider>
            </BrowserRouter>
        </ErrorBoundary>
    );
}

export default App;
