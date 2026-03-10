import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import { ThemeProvider } from './contexts/ThemeContext';
import { ToastContainer } from './components/ui/Toast';
import Layout from './components/layout/Layout';
import Login from './pages/Login';
import OperatorDashboard from './pages/operator/OperatorDashboard';
import CompanyDashboard from './pages/company/Dashboard';
import Drivers from './pages/company/Drivers';
import CompanyTransactions from './pages/company/Transactions';
import Locations from './pages/company/Locations';
import Contracts from './pages/company/Contracts';
import AdminDashboard from './pages/admin/Dashboard';
import Companies from './pages/admin/Companies';
import Users from './pages/admin/Users';
import AdminTransactions from './pages/admin/Transactions';
import WhatsAppLogs from './pages/admin/WhatsAppLogs';
import DriverPerformance from './pages/company/DriverPerformance';
import LocationDetail from './pages/company/LocationDetail';
import Staff from './pages/company/Staff';

// Role mapping: database uses 'admin', 'manager', 'valet'
// admin = super admin (full system access)
// company = company owner (multi-location view)
// valet = operator at a specific location

const ProtectedRoute = ({ children, allowedRoles }) => {
    const { user, role, loading } = useAuth();
    if (loading) return <div className="min-h-screen bg-dark-900 flex items-center justify-center"><div className="animate-spin h-8 w-8 border-2 border-brand-500 border-t-transparent rounded-full" /></div>;
    if (!user) return <Navigate to="/login" replace />;
    if (allowedRoles && !allowedRoles.includes(role)) {
        if (role === 'admin') return <Navigate to="/admin" replace />;
        if (role === 'company') return <Navigate to="/company" replace />;
        return <Navigate to="/operator" replace />;
    }
    return <Layout>{children}</Layout>;
};

const AuthGate = () => {
    const { user, role, loading } = useAuth();
    if (loading) return <div className="min-h-screen bg-dark-900 flex items-center justify-center"><div className="animate-spin h-8 w-8 border-2 border-brand-500 border-t-transparent rounded-full" /></div>;
    if (!user) return <Navigate to="/login" replace />;
    if (role === 'admin') return <Navigate to="/admin" replace />;
    if (role === 'company') return <Navigate to="/company" replace />;
    return <Navigate to="/operator" replace />;
};

function App() {
    return (
        <BrowserRouter>
            <ThemeProvider>
                <AuthProvider>
                    <ToastContainer />
                    <Routes>
                        <Route path="/login" element={<Login />} />
                        <Route path="/" element={<AuthGate />} />

                        <Route path="/operator" element={<ProtectedRoute allowedRoles={['valet', 'company', 'admin']}><OperatorDashboard /></ProtectedRoute>} />

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
                        <Route path="/admin/users" element={<ProtectedRoute allowedRoles={['admin']}><Users /></ProtectedRoute>} />
                        <Route path="/admin/transactions" element={<ProtectedRoute allowedRoles={['admin']}><AdminTransactions /></ProtectedRoute>} />
                        <Route path="/admin/logs" element={<ProtectedRoute allowedRoles={['admin']}><WhatsAppLogs /></ProtectedRoute>} />

                        <Route path="*" element={<Navigate to="/" replace />} />
                    </Routes>
                </AuthProvider>
            </ThemeProvider>
        </BrowserRouter>
    );
}

export default App;
