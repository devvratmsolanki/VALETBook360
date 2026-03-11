import { supabase } from '../lib/supabase';

export const getLocationsByCompany = async (companyId) => {
    const { data, error } = await supabase.from('locations').select('*').eq('valet_company_id', companyId).order('name');
    if (error) throw error;
    return data || [];
};

export const getLocations = async () => {
    const { data, error } = await supabase.from('locations').select('*, valet_companies:valet_company_id(company_name)').order('name');
    if (error) throw error;
    return data || [];
};

export const createLocation = async (locationData) => {
    const mappedData = {
        valet_company_id: locationData.companyId || locationData.valet_company_id,
        name: locationData.name,
        address: locationData.address,
        city: locationData.city,
        state: locationData.state,
        country: locationData.country,
        key_capacity: locationData.keyCapacity || locationData.key_capacity,
        ...locationData
    };
    const { data, error } = await supabase.from('locations').insert(mappedData).select().single();
    if (error) throw error;
    return data;
};

export const updateLocation = async (id, locationData) => {
    const mappedData = {
        name: locationData.name,
        address: locationData.address,
        city: locationData.city,
        state: locationData.state,
        country: locationData.country,
        key_capacity: locationData.keyCapacity || locationData.key_capacity,
        ...locationData
    };
    const { data, error } = await supabase.from('locations').update(mappedData).eq('id', id).select().single();
    if (error) throw error;
    return data;
};

export const deleteLocation = async (id) => {
    const { error } = await supabase.from('locations').delete().eq('id', id);
    if (error) throw error;
};
