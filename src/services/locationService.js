import { supabase } from '../lib/supabase';

export const getLocationsByCompany = async (companyId) => {
    const { data, error } = await supabase.from('locations').select('*').eq('valet_company_id', companyId).order('name');
    if (error) throw error;
    return data || [];
};

export const getAllLocations = async () => {
    const { data, error } = await supabase.from('locations').select('*, valet_companies:valet_company_id(company_name)').order('name');
    if (error) throw error;
    return data || [];
};

export const createLocation = async (location) => {
    const { data, error } = await supabase.from('locations').insert({
        ...location,
        key_capacity: parseInt(location.key_capacity) || 0
    }).select().single();
    if (error) throw error;
    return data;
};

export const updateLocation = async (id, updates) => {
    const { data, error } = await supabase.from('locations').update(updates).eq('id', id).select().single();
    if (error) throw error;
    return data;
};

export const deleteLocation = async (id) => {
    const { error } = await supabase.from('locations').delete().eq('id', id);
    if (error) throw error;
};
