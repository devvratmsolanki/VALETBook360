import { useState, useEffect } from 'react';
import { getWhatsAppLogs } from '../../services/whatsappService';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import Card from '../../components/ui/Card';
import Badge from '../../components/ui/Badge';
import { toast } from '../../components/ui/Toast';
import { Search, Send, ArrowDownLeft, Phone } from 'lucide-react';

const WhatsAppLogs = () => {
    const [logs, setLogs] = useState([]);
    const [filtered, setFiltered] = useState([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');

    const fetchLogs = async () => {
        try {
            const data = await getWhatsAppLogs();
            setLogs(data);
            setFiltered(data);
        } catch {
            toast.error('Failed to load logs');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => { fetchLogs(); }, []);

    useEffect(() => {
        if (!search) { setFiltered(logs); return; }
        const s = search.toLowerCase();
        setFiltered(logs.filter(l =>
            l.phone?.toLowerCase().includes(s) ||
            l.message_body?.toLowerCase().includes(s) ||
            l.visitors?.name?.toLowerCase().includes(s)
        ));
    }, [search, logs]);

    const formatDateTime = (dateStr) => {
        return new Date(dateStr).toLocaleString('en-IN', {
            day: '2-digit',
            month: 'short',
            hour: '2-digit',
            minute: '2-digit',
            hour12: false
        });
    };

    if (loading) return <div className="flex items-center justify-center h-64"><LoadingSpinner size="lg" /></div>;

    return (
        <div className="animate-fade-in">
            <div className="flex items-center justify-between mb-6">
                <div>
                    <h1 className="text-2xl font-bold text-white">WhatsApp Logs</h1>
                    <p className="text-sm text-gray-500 mt-1">{logs.length} messages</p>
                </div>
            </div>

            <div className="mb-6">
                <div className="relative">
                    <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500" />
                    <input
                        type="text"
                        value={search}
                        onChange={(e) => setSearch(e.target.value)}
                        placeholder="Search by phone, name, or message..."
                        className="block w-full max-w-md rounded-xl border-0 bg-dark-600 py-2.5 pl-10 pr-4 text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all"
                    />
                </div>
            </div>

            {filtered.length === 0 ? (
                <Card className="p-8 text-center text-gray-500 text-sm">
                    <Send className="h-8 w-8 text-gray-600 mx-auto mb-3" />
                    <p>No messages found</p>
                </Card>
            ) : (
                <div className="space-y-3">
                    {filtered.map((log) => (
                        <Card key={log.id} className="p-4">
                            <div className="flex items-start gap-3">
                                <div className={`p-2 rounded-xl ${log.direction === 'outbound' ? 'bg-emerald-500/10' : 'bg-blue-500/10'}`}>
                                    {log.direction === 'outbound' ? <Send className="h-4 w-4 text-emerald-400" /> : <ArrowDownLeft className="h-4 w-4 text-blue-400" />}
                                </div>
                                <div className="flex-1 min-w-0">
                                    <div className="flex items-center justify-between mb-1">
                                        <div className="flex items-center gap-2">
                                            <p className="text-sm font-medium text-white">{log.visitors?.name || 'Unknown Guest'}</p>
                                            <span className="text-[10px] text-gray-600 flex items-center gap-1"><Phone className="h-2.5 w-2.5" />{log.phone}</span>
                                        </div>
                                        <span className="text-[10px] text-gray-500">{formatDateTime(log.created_at)}</span>
                                    </div>
                                    <p className="text-sm text-gray-300 line-clamp-2">{log.message_body || 'No content'}</p>
                                    <div className="flex items-center gap-2 mt-2">
                                        <Badge className={log.direction === 'outbound' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20' : 'bg-blue-500/10 text-blue-400 border-blue-500/20'}>
                                            {log.direction}
                                        </Badge>
                                        {log.status && (
                                            <Badge className="bg-gray-500/10 text-gray-500 border-gray-500/20">
                                                {log.status}
                                            </Badge>
                                        )}
                                    </div>
                                </div>
                            </div>
                        </Card>
                    ))}
                </div>
            )}
        </div>
    );
};

export default WhatsAppLogs;
