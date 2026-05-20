import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { getCompanies, createCompanyWithOwner, deleteCompany } from '../../services/companyService';
import { isValidEmail, isValidPhone, isValidPassword, normalizePhone } from '../../lib/utils';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Modal from '../../components/ui/Modal';
import Input from '../../components/ui/Input';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import { toast } from '../../components/ui/Toast';
import { Building2, Plus, Trash2, Phone, Mail, Key, User, Eye, EyeOff, ChevronRight } from 'lucide-react';

const emptyForm = { company_name: '', owner_name: '', phone: '', email: '', password: '' };

const Companies = () => {
    const navigate = useNavigate();
    const [companies, setCompanies] = useState([]);
    const [loading, setLoading] = useState(true);
    const [showModal, setShowModal] = useState(false);
    const [formData, setFormData] = useState(emptyForm);
    const [errors, setErrors] = useState({});
    const [saving, setSaving] = useState(false);
    const [showPassword, setShowPassword] = useState(false);

    const fetchCompanies = async () => {
        try {
            setCompanies(await getCompanies());
        } catch (err) {
            toast.error(err?.message || 'Failed to load companies');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => { fetchCompanies(); }, []);

    const validate = () => {
        const next = {};
        if (!formData.company_name.trim()) next.company_name = 'Required';
        if (!formData.owner_name.trim()) next.owner_name = 'Required';
        if (!isValidPhone(formData.phone)) next.phone = 'Enter a valid phone (7–15 digits)';
        if (!isValidEmail(formData.email)) next.email = 'Enter a valid email';
        if (!isValidPassword(formData.password)) next.password = 'Min 8 chars with a letter and a number';
        setErrors(next);
        return Object.keys(next).length === 0;
    };

    const handleCreate = async (e) => {
        e.preventDefault();
        if (!validate()) return;
        setSaving(true);
        try {
            await createCompanyWithOwner({
                company_name: formData.company_name.trim(),
                owner_name: formData.owner_name.trim(),
                phone: normalizePhone(formData.phone),
                email: formData.email.trim().toLowerCase(),
                password: formData.password,
            });
            toast.success('Company and owner account created');
            setShowModal(false);
            setFormData(emptyForm);
            setErrors({});
            fetchCompanies();
        } catch (err) {
            toast.error(err.message || 'Failed to create company');
        } finally {
            setSaving(false);
        }
    };

    const handleDelete = async (id, e) => {
        e?.stopPropagation();
        if (!confirm('Delete this company? Linked locations, drivers and staff stay but become orphaned.')) return;
        try {
            await deleteCompany(id);
            toast.success('Deleted');
            fetchCompanies();
        } catch (err) {
            toast.error(err?.message || 'Failed to delete');
        }
    };

    const closeModal = () => {
        setShowModal(false);
        setFormData(emptyForm);
        setErrors({});
        setShowPassword(false);
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
                        <Card
                            key={c.id}
                            className="p-5 cursor-pointer hover:border-brand-500/20 hover:bg-white/[0.02] transition-all group"
                            onClick={() => navigate(`/admin/companies/${c.id}`)}
                        >
                            <div className="flex items-start justify-between mb-3">
                                <div className="flex items-center gap-3">
                                    <div className="bg-brand-500/10 p-2 rounded-xl">
                                        <Building2 className="h-5 w-5 text-brand-400" />
                                    </div>
                                    <p className="font-medium text-white">{c.company_name}</p>
                                </div>
                                <div className="flex items-center gap-1">
                                    <button
                                        onClick={(e) => handleDelete(c.id, e)}
                                        className="p-1.5 rounded-lg hover:bg-red-500/10 text-gray-600 hover:text-red-400 transition-colors"
                                    >
                                        <Trash2 className="h-4 w-4" />
                                    </button>
                                    <ChevronRight className="h-4 w-4 text-gray-600 group-hover:text-brand-400 transition-colors" />
                                </div>
                            </div>
                            <div className="space-y-1.5 text-xs text-gray-400 border-t border-white/5 pt-3">
                                <p>Owner: {c.owner_name || 'N/A'}</p>
                                {c.phone && <p className="flex items-center gap-1"><Phone className="h-3 w-3 text-gray-600" /> {c.phone}</p>}
                                {c.email && <p className="flex items-center gap-1"><Mail className="h-3 w-3 text-gray-600" /> {c.email}</p>}
                            </div>
                            <p className="text-[10px] text-gray-600 mt-3 group-hover:text-brand-400 transition-colors">Click to manage locations, operators & drivers →</p>
                        </Card>
                    ))}
                </div>
            )}

            <Modal isOpen={showModal} onClose={closeModal} title="Add Company">
                <form onSubmit={handleCreate} className="space-y-4">
                    <Input
                        label="Company Name"
                        icon={Building2}
                        required
                        value={formData.company_name}
                        onChange={(e) => setFormData({ ...formData, company_name: e.target.value })}
                        placeholder="Company name"
                        error={errors.company_name}
                    />
                    <Input
                        label="Owner Name"
                        icon={User}
                        required
                        value={formData.owner_name}
                        onChange={(e) => setFormData({ ...formData, owner_name: e.target.value })}
                        placeholder="Owner full name"
                        error={errors.owner_name}
                    />
                    <Input
                        label="Phone"
                        icon={Phone}
                        required
                        inputMode="tel"
                        value={formData.phone}
                        onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
                        placeholder="e.g. 9876543210"
                        error={errors.phone}
                    />
                    <Input
                        label="Login Email"
                        icon={Mail}
                        type="email"
                        required
                        autoComplete="off"
                        value={formData.email}
                        onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                        placeholder="owner@example.com"
                        error={errors.email}
                    />
                    <div className="space-y-1.5">
                        <label className="block text-sm font-medium text-gray-300">Initial Password</label>
                        <div className="relative group">
                            <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3.5">
                                <Key className="h-4 w-4 text-gray-500 group-focus-within:text-brand-500 transition-colors" />
                            </div>
                            <input
                                type={showPassword ? 'text' : 'password'}
                                required
                                autoComplete="new-password"
                                value={formData.password}
                                onChange={(e) => setFormData({ ...formData, password: e.target.value })}
                                placeholder="Min 8 chars, letter + number"
                                className={`block w-full rounded-xl border-0 bg-dark-600 py-3 pl-10 pr-10 text-gray-200 placeholder:text-gray-500 ring-1 ring-inset ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all ${errors.password ? 'ring-red-500/50' : ''}`}
                            />
                            <button type="button" onClick={() => setShowPassword(s => !s)} className="absolute inset-y-0 right-0 flex items-center pr-3 text-gray-500 hover:text-gray-300">
                                {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                            </button>
                        </div>
                        {errors.password
                            ? <p className="text-xs text-red-400">{errors.password}</p>
                            : <p className="text-[11px] text-gray-500">Share this with the owner — they can change it after first login.</p>}
                    </div>

                    <div className="flex justify-end gap-3 pt-2">
                        <Button variant="ghost" type="button" onClick={closeModal}>Cancel</Button>
                        <Button type="submit" disabled={saving}>{saving ? 'Creating...' : 'Create Company'}</Button>
                    </div>
                </form>
            </Modal>
        </div>
    );
};

export default Companies;
