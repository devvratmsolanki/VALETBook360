import { supabase } from '../lib/supabase';

export const getAllUsers = async () => {
    const { data, error } = await supabase.from('users').select('*, valet_companies:valet_company_id(company_name)').order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
};

export const createUser = async (user) => {
    const { data, error } = await supabase.from('users').insert(user).select().single();
    if (error) throw error;
    return data;
};

export const updateUserRole = async (id, role) => {
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
    const { data, error } = await supabase.from('users').update(updates).eq('id', id).select().single();
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
