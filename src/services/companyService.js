import { supabase } from '../lib/supabase';

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

export const updateCompany = async (id, updates) => {
    const { data, error } = await supabase.from('valet_companies').update(updates).eq('id', id).select().single();
    if (error) throw error;
    return data;
};

export const deleteCompany = async (id) => {
    const { error } = await supabase.from('valet_companies').delete().eq('id', id);
    if (error) throw error;
};
