import { supabase } from '../lib/supabase';
import { createStaff } from './userService';

export const getCompanies = async () => {
    const { data, error } = await supabase.from('valet_companies').select('*').order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
};

export const createCompany = async (company) => {
    const { data, error } = await supabase.from('valet_companies').insert(company).select().single();
    if (error) throw error;
    return data;
};

// Creates the company row AND the auth user that will sign in as that company.
// If the user creation fails, the company row is deleted so the admin can retry
// with the same name/email without hitting a unique-constraint conflict.
export const createCompanyWithOwner = async ({ company_name, owner_name, phone, email, password }) => {
    const company = await createCompany({ company_name, owner_name, phone, email });
    try {
        await createStaff({
            email,
            password,
            name: owner_name || company_name,
            role: 'company',
            company_id: company.id,
            location_id: null,
        });
    } catch (err) {
        await supabase.from('valet_companies').delete().eq('id', company.id);
        throw err;
    }
    return company;
};

export const updateCompany = async (id, updates) => {
    const { data, error } = await supabase.from('valet_companies').update(updates).eq('id', id).select().single();
    if (error) throw error;
    return data;
};

export const deleteCompany = async (id) => {
    const { error } = await supabase.from('valet_companies').delete().eq('id', id);
    if (error) throw error;
};
