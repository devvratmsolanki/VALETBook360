import { useState, useEffect } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { getUsersByCompany, updateUser, deleteUser, createStaff } from '../../services/userService';
import { getLocationsByCompany } from '../../services/locationService';
import Card from '../../components/ui/Card';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import { toast } from '../../components/ui/Toast';
import { Users as UsersIcon, MapPin, Shield, Mail, Trash2, Edit2, Check, X, Plus, Key } from 'lucide-react';

const Staff = () => {
    const { companyId, user: currentUser } = useAuth();
    const [staff, setStaff] = useState([]);
    const [locations, setLocations] = useState([]);
    const [loading, setLoading] = useState(true);

    // Edit state
    const [editingId, setEditingId] = useState(null);
    const [editForm, setEditForm] = useState({ role: '', location_id: '' });

    // Add state
    const [isAddModalOpen, setIsAddModalOpen] = useState(false);
    const [addForm, setAddForm] = useState({ name: '', email: '', password: '', role: 'valet', location_id: '' });
    const [adding, setAdding] = useState(false);

    const fetchData = async () => {
        try {
            const [usersData, locsData] = await Promise.all([
                getUsersByCompany(companyId),
                getLocationsByCompany(companyId)
            ]);
            setStaff(usersData);
            setLocations(locsData);
        } catch (err) {
            toast.error('Failed to load team data');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        if (companyId) fetchData();
    }, [companyId]);

    const startEdit = (user) => {
        setEditingId(user.id);
        setEditForm({ role: user.role, location_id: user.location_id || '' });
    };

    const handleSave = async (id) => {
        try {
            await updateUser(id, {
                role: editForm.role,
                location_id: editForm.location_id === '' ? null : editForm.location_id
            });
            toast.success('Staff member updated');
            setEditingId(null);
            fetchData();
        } catch (err) {
            toast.error('Failed to update staff member');
        }
    };

    const handleAddStaff = async (e) => {
        e.preventDefault();
        setAdding(true);
        try {
            await createStaff({
                ...addForm,
                company_id: companyId,
                location_id: addForm.role === 'valet' ? (addForm.location_id || null) : null
            });
            toast.success('Staff member created');
            setIsAddModalOpen(false);
            setAddForm({ name: '', email: '', password: '', role: 'valet', location_id: '' });
            fetchData();
        } catch (err) {
            toast.error(err.message || 'Failed to create staff member');
        } finally {
            setAdding(false);
        }
    };

    const handleDelete = async (user) => {
        if (user.id === currentUser?.id) return toast.error("You cannot remove yourself");
        if (!confirm(`Are you sure you want to PERMANENTLY remove "${user.name || user.email}"? This action cannot be undone.`)) return;
        try {
            await deleteUser(user.id);
            toast.success('Staff member removed permanently');
            fetchData();
        } catch (err) {
            toast.error('Failed to remove staff member');
        }
    };

    const roles = ['company', 'valet'];
    const getRoleStyle = (r) => ({
        company: 'bg-blue-500/10 text-blue-400 border-blue-500/20',
        valet: 'bg-brand-500/10 text-brand-400 border-brand-500/20'
    }[r] || '');

    if (loading) return <div className="flex justify-center py-12"><LoadingSpinner size="md" /></div>;

    return (
        <div className="animate-fade-in">
            <div className="flex items-center justify-between mb-6">
                <div>
                    <h1 className="text-2xl font-bold text-white">Team Management</h1>
                    <p className="text-sm text-gray-500 mt-1">Add, edit and manage your staff members</p>
                </div>
                <Button onClick={() => setIsAddModalOpen(true)} className="flex items-center gap-2">
                    <Plus className="h-4 w-4" /> Add Member
                </Button>
            </div>

            {/* Add Member Modal */}
            {isAddModalOpen && (
                <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
                    <Card className="w-full max-w-md p-6 animate-in slide-in-from-bottom-4">
                        <div className="flex items-center justify-between mb-6">
                            <h2 className="text-xl font-bold text-white">Add Team Member</h2>
                            <button onClick={() => setIsAddModalOpen(false)} className="text-gray-400 hover:text-white"><X className="h-5 w-5" /></button>
                        </div>
                        <form onSubmit={handleAddStaff} className="space-y-4">
                            <div>
                                <label className="block text-xs font-medium text-gray-400 mb-1">Full Name</label>
                                <input type="text" required value={addForm.name} onChange={e => setAddForm({ ...addForm, name: e.target.value })} className="w-full bg-dark-600 border-white/5 rounded-xl px-4 py-2.5 text-sm text-white focus:ring-2 focus:ring-brand-500/50" placeholder="John Doe" />
                            </div>
                            <div>
                                <label className="block text-xs font-medium text-gray-400 mb-1">Email Address</label>
                                <input type="email" required value={addForm.email} onChange={e => setAddForm({ ...addForm, email: e.target.value })} className="w-full bg-dark-600 border-white/5 rounded-xl px-4 py-2.5 text-sm text-white focus:ring-2 focus:ring-brand-500/50" placeholder="john@example.com" />
                            </div>
                            <div>
                                <label className="block text-xs font-medium text-gray-400 mb-1">Password</label>
                                <div className="relative">
                                    <Key className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500" />
                                    <input type="password" required value={addForm.password} onChange={e => setAddForm({ ...addForm, password: e.target.value })} className="w-full bg-dark-600 border-white/5 rounded-xl pl-10 pr-4 py-2.5 text-sm text-white focus:ring-2 focus:ring-brand-500/50" placeholder="••••••••" />
                                </div>
                            </div>
                            <div className="grid grid-cols-2 gap-4">
                                <div>
                                    <label className="block text-xs font-medium text-gray-400 mb-1">Role</label>
                                    <select value={addForm.role} onChange={e => setAddForm({ ...addForm, role: e.target.value })} className="w-full bg-dark-600 border-white/5 rounded-xl px-4 py-2.5 text-sm text-white focus:ring-2 focus:ring-brand-500/50">
                                        <option value="valet">Valet</option>
                                        <option value="company">Company Staff</option>
                                    </select>
                                </div>
                                {addForm.role === 'valet' && (
                                    <div>
                                        <label className="block text-xs font-medium text-gray-400 mb-1">Location</label>
                                        <select value={addForm.location_id} onChange={e => setAddForm({ ...addForm, location_id: e.target.value })} className="w-full bg-dark-600 border-white/5 rounded-xl px-4 py-2.5 text-sm text-white focus:ring-2 focus:ring-brand-500/50">
                                            <option value="">No Location</option>
                                            {locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}
                                        </select>
                                    </div>
                                )}
                            </div>
                            <div className="flex gap-3 pt-4">
                                <Button type="button" variant="outline" onClick={() => setIsAddModalOpen(false)} className="flex-1">Cancel</Button>
                                <Button type="submit" disabled={adding} className="flex-1">
                                    {adding ? 'Creating...' : 'Create Account'}
                                </Button>
                            </div>
                        </form>
                    </Card>
                </div>
            )}

            {staff.length === 0 ? (
                <Card className="p-8 text-center text-gray-500">No staff members found.</Card>
            ) : (
                <Card className="overflow-hidden">
                    <div className="overflow-x-auto">
                        <table className="w-full text-left text-sm">
                            <thead className="bg-dark-700/50 text-xs uppercase text-gray-500">
                                <tr>
                                    <th className="px-6 py-3">Member</th>
                                    <th className="px-6 py-3">Role</th>
                                    <th className="px-6 py-3">Assigned Location</th>
                                    <th className="px-6 py-3 text-right">Actions</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-white/5">
                                {staff.map((u) => (
                                    <tr key={u.id} className="hover:bg-white/[0.02] transition-colors">
                                        <td className="px-6 py-4">
                                            <div className="flex items-center gap-3">
                                                <div className="h-8 w-8 rounded-full bg-gradient-to-br from-brand-400 to-brand-600 flex items-center justify-center text-black text-xs font-bold">
                                                    {u.name?.charAt(0)?.toUpperCase() || '?'}
                                                </div>
                                                <div>
                                                    <p className="font-medium text-white text-sm">{u.name || 'No Name'}</p>
                                                    <p className="text-xs text-gray-500">{u.email}</p>
                                                </div>
                                            </div>
                                        </td>
                                        <td className="px-6 py-4">
                                            {editingId === u.id ? (
                                                <select
                                                    value={editForm.role}
                                                    onChange={(e) => setEditForm({ ...editForm, role: e.target.value })}
                                                    className="bg-dark-600 border-white/10 text-gray-200 text-xs rounded-lg px-2 py-1"
                                                >
                                                    {roles.map(r => <option key={r} value={r}>{r}</option>)}
                                                </select>
                                            ) : (
                                                <Badge className={getRoleStyle(u.role)}>{u.role}</Badge>
                                            )}
                                        </td>
                                        <td className="px-6 py-4">
                                            {editingId === u.id && u.role === 'valet' ? (
                                                <select
                                                    value={editForm.location_id}
                                                    onChange={(e) => setEditForm({ ...editForm, location_id: e.target.value })}
                                                    className="bg-dark-600 border-white/10 text-gray-200 text-xs rounded-lg px-2 py-1 w-full max-w-[200px]"
                                                >
                                                    <option value="">No Location (Mobile/Floating)</option>
                                                    {locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}
                                                </select>
                                            ) : (
                                                <div className="flex items-center gap-2 text-gray-400">
                                                    <MapPin className="h-3.5 w-3.5" />
                                                    <span className="text-sm">{u.location?.name || 'Unassigned'}</span>
                                                </div>
                                            )}
                                        </td>
                                        <td className="px-6 py-4 text-right">
                                            {editingId === u.id ? (
                                                <div className="flex justify-end gap-2">
                                                    <button onClick={() => handleSave(u.id)} className="p-1.5 rounded-lg bg-brand-500/20 text-brand-400 hover:bg-brand-500/30">
                                                        <Check className="h-4 w-4" />
                                                    </button>
                                                    <button onClick={() => setEditingId(null)} className="p-1.5 rounded-lg bg-white/5 text-gray-400 hover:bg-white/10">
                                                        <X className="h-4 w-4" />
                                                    </button>
                                                </div>
                                            ) : (
                                                <div className="flex justify-end gap-2 text-gray-600">
                                                    <button onClick={() => startEdit(u)} className="p-1.5 rounded-lg hover:bg-white/5 hover:text-white transition-colors">
                                                        <Edit2 className="h-4 w-4" />
                                                    </button>
                                                    {u.id !== currentUser?.id && (
                                                        <button onClick={() => handleDelete(u)} className="p-1.5 rounded-lg hover:bg-red-500/10 hover:text-red-400 transition-colors">
                                                            <Trash2 className="h-4 w-4" />
                                                        </button>
                                                    )}
                                                </div>
                                            )}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </Card>
            )}
        </div>
    );
};

export default Staff;
