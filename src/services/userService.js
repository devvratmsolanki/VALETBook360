import { supabase } from '../lib/supabase';

export const getUsers = async () => {
    const { data, error } = await supabase.from('users').select('*, valet_companies:valet_company_id(company_name)').order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
};

export const createUser = async (user) => {
    const { data, error } = await supabase.from('users').insert(user).select().single();
    if (error) throw error;
    return data;
};

// Client-side role validation. RLS on the `users` table must also enforce
// these rules — this check only catches honest UI bugs, not a determined
// attacker bypassing the client.
const ASSIGNABLE_ROLES = new Set(['company', 'valet', 'driver']);

const assertRoleAssignable = (role) => {
    if (role === undefined || role === null) return;
    if (!ASSIGNABLE_ROLES.has(role)) {
        throw new Error(`Role "${role}" cannot be assigned from the client. Use the SQL editor to promote admins.`);
    }
};

export const updateUserRole = async (id, role) => {
    assertRoleAssignable(role);
    const { data, error } = await supabase.from('users').update({ role }).eq('id', id).select().single();
    if (error) throw error;
    return data;
};

export const getUsersByCompany = async (companyId) => {
    const { data, error } = await supabase
        .from('users')
        .select('*, location:location_id(id, name)')
        .eq('valet_company_id', companyId)
        .order('name');
    if (error) throw error;
    return data || [];
};

export const createStaff = async (userData) => {
    const { data: { session } } = await supabase.auth.getSession();
    const response = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/create-staff`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session?.access_token}`,
        },
        body: JSON.stringify(userData),
    });

    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'Failed to create staff member');
    return result;
};

export const updateUser = async (id, updates) => {
    // Whitelist fields. Without this, a caller could pass arbitrary keys
    // (including `valet_company_id`) and reassign users to other companies.
    const allowed = {};
    if (updates.name !== undefined) allowed.name = updates.name;
    if (updates.email !== undefined) allowed.email = updates.email;
    if (updates.location_id !== undefined) allowed.location_id = updates.location_id;
    if (updates.role !== undefined) {
        assertRoleAssignable(updates.role);
        allowed.role = updates.role;
    }
    const { data, error } = await supabase.from('users').update(allowed).eq('id', id).select().single();
    if (error) throw error;
    return data;
};

export const deleteUser = async (id) => {
    // For permanent deletion, we'd need another edge function or Admin API access
    // For now, we'll unlink them from the company and mark them as inactive/locked if possible
    // But since the user asked for "delete", let's try to remove the profile record
    // Note: The Auth user will remain unless deleted via Admin API/Edge Function
    const { error } = await supabase.from('users').delete().eq('id', id);
    if (error) throw error;
};
