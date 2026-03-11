import { supabase } from '../lib/supabase';

export const getDriversByCompany = async (companyId) => {
    const { data, error } = await supabase.from('drivers').select('*, contracts(locations:location_id(name))').eq('valet_company_id', companyId).order('staff_id', { ascending: true });
    if (error) throw error;
    return data || [];
};

export const getDrivers = async () => {
    const { data, error } = await supabase.from('drivers').select('*, valet_companies:valet_company_id(company_name)').order('staff_id', { ascending: true });
    if (error) throw error;
    return data || [];
};

export const createDriver = async (driverData) => {
    const mappedData = {
        valet_company_id: driverData.companyId || driverData.valet_company_id,
        name: driverData.name,
        phone: driverData.phone,
        email: driverData.email,
        staff_id: driverData.staffId || driverData.staff_id,
        active: driverData.active ?? true,
        ...driverData
    };
    const { data, error } = await supabase.from('drivers').insert(mappedData).select().single();
    if (error) throw error;
    return data;
};

export const updateDriver = async (id, driverData) => {
    const mappedData = {
        name: driverData.name,
        phone: driverData.phone,
        email: driverData.email,
        staff_id: driverData.staffId || driverData.staff_id,
        active: driverData.active,
        ...driverData
    };
    const { data, error } = await supabase.from('drivers').update(mappedData).eq('id', id).select().single();
    if (error) throw error;
    return data;
};

export const toggleDriverActive = async (id, active) => updateDriver(id, { active });
