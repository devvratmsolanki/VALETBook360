import { supabase } from '../lib/supabase';

export const getDriversByCompany = async (companyId) => {
    const { data, error } = await supabase.from('drivers').select('*, contracts(locations:location_id(name))').eq('valet_company_id', companyId).order('staff_id', { ascending: true });
    if (error) throw error;
    return data || [];
};

export const getAllDrivers = async () => {
    const { data, error } = await supabase.from('drivers').select('*, valet_companies:valet_company_id(company_name)').order('staff_id', { ascending: true });
    if (error) throw error;
    return data || [];
};

export const createDriver = async (driver) => {
    // Auto-generate staff_id if not present
    if (!driver.staff_id) {
        const randomNum = Math.floor(1000 + Math.random() * 9000);
        driver.staff_id = `VD-${randomNum}`;
    }
    const { data, error } = await supabase.from('drivers').insert(driver).select().single();
    if (error) throw error;
    return data;
};

export const updateDriver = async (id, updates) => {
    const { data, error } = await supabase.from('drivers').update(updates).eq('id', id).select().single();
    if (error) throw error;
    return data;
};

export const toggleDriverActive = async (id, active) => updateDriver(id, { active });
