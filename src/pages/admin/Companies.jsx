import { useState, useEffect } from 'react';
import { getCompanies, createCompany, deleteCompany } from '../../services/companyService';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Modal from '../../components/ui/Modal';
import Input from '../../components/ui/Input';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import { toast } from '../../components/ui/Toast';
import { Building2, Plus, Trash2, Phone, Mail } from 'lucide-react';

const Companies = () => {
    const [companies, setCompanies] = useState([]);
    const [loading, setLoading] = useState(true);
    const [showModal, setShowModal] = useState(false);
    const [formData, setFormData] = useState({ company_name: '', owner_name: '', phone: '', email: '' });
    const [saving, setSaving] = useState(false);

    const fetchCompanies = async () => {
        try {
            const data = await getCompanies();
            setCompanies(data);
        } catch {
            toast.error('Failed to load companies');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => { fetchCompanies(); }, []);

    const handleCreate = async (e) => {
        e.preventDefault();
        setSaving(true);
        try {
            await createCompany(formData);
            toast.success('Company created');
            setShowModal(false);
            setFormData({ company_name: '', owner_name: '', phone: '', email: '' });
            fetchCompanies();
        } catch (err) {
            toast.error(err.message);
        } finally {
            setSaving(false);
        }
    };

    const handleDelete = async (id) => {
        if (!confirm('Delete this company?')) return;
        try {
            await deleteCompany(id);
            toast.success('Deleted');
            fetchCompanies();
        } catch {
            toast.error('Failed to delete');
        }
    };

    if (loading) return <div className="flex items-center justify-center h-64"><LoadingSpinner size="lg" /></div>;

    return (
        <div className="animate-fade-in">
            <div className="flex items-center justify-between mb-6">
                <div>
                    <h1 className="text-2xl font-bold text-white">Companies</h1>
                    <p className="text-sm text-gray-500 mt-1">{companies.length} registered companies</p>
                </div>
                <Button onClick={() => setShowModal(true)}>
                    <Plus className="h-4 w-4" /> Add Company
                </Button>
            </div>

            {companies.length === 0 ? (
                <Card className="p-8 text-center">
                    <Building2 className="h-8 w-8 text-gray-600 mx-auto mb-3" />
                    <p className="text-gray-500">No companies yet</p>
                </Card>
            ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                    {companies.map((c) => (
                        <Card key={c.id} className="p-5">
                            <div className="flex items-start justify-between mb-3">
                                <div className="flex items-center gap-3">
                                    <div className="bg-brand-500/10 p-2 rounded-xl">
                                        <Building2 className="h-5 w-5 text-brand-400" />
                                    </div>
                                    <p className="font-medium text-white">{c.company_name}</p>
                                </div>
                                <button onClick={() => handleDelete(c.id)} className="p-1.5 rounded-lg hover:bg-red-500/10 text-gray-600 hover:text-red-400 transition-colors">
                                    <Trash2 className="h-4 w-4" />
                                </button>
                            </div>
                            <div className="space-y-1.5 text-xs text-gray-400 border-t border-white/5 pt-3">
                                <p>Owner: {c.owner_name || 'N/A'}</p>
                                {c.phone && <p className="flex items-center gap-1"><Phone className="h-3 w-3 text-gray-600" /> {c.phone}</p>}
                                {c.email && <p className="flex items-center gap-1"><Mail className="h-3 w-3 text-gray-600" /> {c.email}</p>}
                            </div>
                        </Card>
                    ))}
                </div>
            )}

            <Modal isOpen={showModal} onClose={() => setShowModal(false)} title="Add Company">
                <form onSubmit={handleCreate} className="space-y-4">
                    <Input label="Company Name" required value={formData.company_name} onChange={(e) => setFormData({ ...formData, company_name: e.target.value })} placeholder="Company name" />
                    <Input label="Owner" value={formData.owner_name} onChange={(e) => setFormData({ ...formData, owner_name: e.target.value })} placeholder="Owner name" />
                    <Input icon={Phone} label="Phone" value={formData.phone} onChange={(e) => setFormData({ ...formData, phone: e.target.value })} placeholder="Phone" />
                    <Input icon={Mail} label="Email" value={formData.email} onChange={(e) => setFormData({ ...formData, email: e.target.value })} placeholder="Email" />
                    <div className="flex justify-end gap-3 pt-2">
                        <Button variant="ghost" type="button" onClick={() => setShowModal(false)}>Cancel</Button>
                        <Button type="submit" disabled={saving}>{saving ? 'Creating...' : 'Create Company'}</Button>
                    </div>
                </form>
            </Modal>
        </div>
    );
};

export default Companies;
