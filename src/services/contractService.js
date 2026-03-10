import { supabase } from '../lib/supabase';

export const getContractsByCompany = async (companyId) => {
    const { data, error } = await supabase.from('contracts').select('*, locations:location_id(*)').eq('valet_company_id', companyId).order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
};

export const getAllContracts = async () => {
    const { data, error } = await supabase.from('contracts').select('*, locations:location_id(*), valet_companies:valet_company_id(company_name)').order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
};

export const createContract = async (contract) => {
    const { data, error } = await supabase.from('contracts').insert(contract).select().single();
    if (error) throw error;
    return data;
};

export const updateContract = async (id, updates) => {
    const { data, error } = await supabase.from('contracts').update(updates).eq('id', id).select().single();
    if (error) throw error;
    return data;
};
