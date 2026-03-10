import { useState, useEffect } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { getContractsByCompany } from '../../services/contractService';
import Card from '../../components/ui/Card';
import Badge from '../../components/ui/Badge';
import { toast } from '../../components/ui/Toast';
import { FileText, MapPin, Phone, Mail, CheckCircle, XCircle } from 'lucide-react';

const Contracts = () => {
    const { companyId } = useAuth();
    const [contracts, setContracts] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => { const f = async () => { try { setContracts(companyId ? await getContractsByCompany(companyId) : []); } catch { toast.error('Failed to load'); } finally { setLoading(false); } }; f(); }, [companyId]);

    return (
        <div className="animate-fade-in">
            <div className="mb-6"><h1 className="text-2xl font-bold text-white">Contracts</h1><p className="text-sm text-gray-500 mt-1">{contracts.length} contracts</p></div>
            {loading ? <div className="flex justify-center py-12"><div className="animate-spin h-6 w-6 border-2 border-brand-500 border-t-transparent rounded-full" /></div> : contracts.length === 0 ? <Card className="p-8 text-center"><FileText className="h-8 w-8 text-gray-600 mx-auto mb-3" /><p className="text-gray-500">No contracts found</p></Card> : (
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">{contracts.map((c) => (<Card key={c.id} className="p-5"><div className="flex items-start justify-between mb-4"><div className="flex items-center gap-3"><div className="bg-blue-500/10 p-2 rounded-xl"><FileText className="h-5 w-5 text-blue-400" /></div><div><p className="font-medium text-white text-sm">{c.locations?.name || 'Unknown Location'}</p><p className="text-xs text-gray-500 flex items-center gap-1 mt-0.5"><MapPin className="h-3 w-3" />{[c.locations?.city, c.locations?.state].filter(Boolean).join(', ') || 'N/A'}</p></div></div><Badge className={c.active ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20' : 'bg-red-500/10 text-red-400 border-red-500/20'}>{c.active ? <><CheckCircle className="h-3 w-3 mr-1" /> Active</> : <><XCircle className="h-3 w-3 mr-1" /> Inactive</>}</Badge></div><div className="border-t border-white/5 pt-3 space-y-2"><p className="text-xs text-gray-400"><span className="text-gray-600">Manager:</span> {c.manager_name || 'N/A'}</p>{c.manager_phone && <p className="text-xs text-gray-400 flex items-center gap-1"><Phone className="h-3 w-3 text-gray-600" /> {c.manager_phone}</p>}{c.manager_email && <p className="text-xs text-gray-400 flex items-center gap-1"><Mail className="h-3 w-3 text-gray-600" /> {c.manager_email}</p>}</div></Card>))}</div>
            )}
        </div>
    );
};

export default Contracts;
