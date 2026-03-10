import { useState } from 'react';
import Sidebar from './Sidebar';
import Header from './Header';

const Layout = ({ children }) => {
    const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

    return (
        <div className="min-h-screen bg-dark-900">
            <Sidebar />
            {mobileMenuOpen && (
                <div className="fixed inset-0 z-50 md:hidden">
                    <div className="fixed inset-0 bg-black/60" onClick={() => setMobileMenuOpen(false)} />
                    <div className="fixed inset-y-0 left-0 w-64"><Sidebar /></div>
                </div>
            )}
            <div className="md:pl-64">
                <Header onMobileMenu={() => setMobileMenuOpen(!mobileMenuOpen)} />
                <main className="p-6 lg:p-8">{children}</main>
            </div>
        </div>
    );
};

export default Layout;
