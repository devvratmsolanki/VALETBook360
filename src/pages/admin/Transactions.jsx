import { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import { getTransactions, updateTransactionStatus } from '../../services/transactionService';
import Card from '../../components/ui/Card';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import { toast } from '../../components/ui/Toast';
import { formatDateTime } from '../../lib/utils';
import { Search, Activity } from 'lucide-react';

const AdminTransactions = () => {
    const [transactions, setTransactions] = useState([]);
    const [filtered, setFiltered] = useState([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');
    const [searchParams] = useSearchParams();
    const [statusFilter, setStatusFilter] = useState(searchParams.get('status') || 'all');

    const fetchData = async () => { try { const d = await getTransactions(); setTransactions(d); setFiltered(d); } catch { toast.error('Failed to load'); } finally { setLoading(false); } };
    useEffect(() => { fetchData(); }, []);
    useEffect(() => { let r = transactions; if (statusFilter !== 'all') r = r.filter(t => t.status === statusFilter); if (search) { const s = search.toLowerCase(); r = r.filter(t => t.cars?.car_number?.toLowerCase().includes(s) || t.visitors?.name?.toLowerCase().includes(s)); } setFiltered(r); }, [search, statusFilter, transactions]);

    const handleStatusUpdate = async (id, status) => { try { await updateTransactionStatus(id, status); toast.success(`Updated to ${status}`); fetchData(); } catch { toast.error('Failed'); } };
    const statuses = ['all', 'parked', 'requested', 'ready', 'delivered'];

    return (
        <div className="animate-fade-in">
            <div className="flex items-center justify-between mb-6"><div><h1 className="text-2xl font-bold text-white">All Transactions</h1><p className="text-sm text-gray-500 mt-1">System-wide transaction analytics</p></div><div className="flex items-center gap-2 bg-dark-700 px-3 py-1.5 rounded-xl"><Activity className="h-4 w-4 text-brand-400" /><span className="text-sm font-medium text-white">{transactions.length}</span></div></div>
            <div className="flex flex-col sm:flex-row gap-3 mb-6"><div className="relative flex-1"><Search className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500" /><input type="text" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search..." className="block w-full rounded-xl border-0 bg-dark-600 py-2.5 pl-10 pr-4 text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all" /></div><div className="flex gap-2">{statuses.map((s) => (<button key={s} onClick={() => setStatusFilter(s)} className={`px-3 py-2 rounded-lg text-xs font-medium capitalize ${statusFilter === s ? 'bg-brand-500/10 text-brand-400 border border-brand-500/20' : 'text-gray-500 hover:text-white hover:bg-white/5 border border-transparent'}`}>{s}</button>))}</div></div>
            <Card className="overflow-hidden">{loading ? <div className="p-8 flex justify-center"><div className="animate-spin h-6 w-6 border-2 border-brand-500 border-t-transparent rounded-full" /></div> : filtered.length === 0 ? <div className="p-8 text-center text-gray-500 text-sm">No transactions found</div> : (
                <div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="bg-dark-700/50 text-xs uppercase text-gray-500"><tr><th className="px-6 py-3">Car Number</th><th className="px-6 py-3">Guest</th><th className="px-6 py-3">Status</th><th className="px-6 py-3">Slot</th><th className="px-6 py-3">Date/Time</th><th className="px-6 py-3">Actions</th></tr></thead><tbody className="divide-y divide-white/5">{filtered.map((tx) => (<tr key={tx.id} className="hover:bg-white/[0.02] transition-colors"><td className="px-6 py-4 font-medium text-white">{tx.cars?.car_number || 'N/A'}</td><td className="px-6 py-4 text-gray-300">{tx.visitors?.name || 'Unknown'}</td><td className="px-6 py-4"><Badge variant={tx.status}>{tx.status}</Badge></td><td className="px-6 py-4 text-gray-500">{tx.parking_slot || '-'}</td><td className="px-6 py-4 text-gray-500 text-xs">{formatDateTime(tx.created_at)}</td><td className="px-6 py-4">{tx.status === 'parked' && <Button size="sm" variant="outline" onClick={() => handleStatusUpdate(tx.id, 'requested')}>Request</Button>}{tx.status === 'requested' && <Button size="sm" variant="outline" className="border-emerald-500/30 text-emerald-400" onClick={() => handleStatusUpdate(tx.id, 'ready')}>Ready</Button>}{tx.status === 'ready' && <Button size="sm" variant="ghost" onClick={() => handleStatusUpdate(tx.id, 'delivered')}>Delivered</Button>}</td></tr>))}</tbody></table></div>
            )}</Card>
        </div>
    );
};

export default AdminTransactions;
