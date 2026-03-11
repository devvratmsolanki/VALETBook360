import { supabase } from '../lib/supabase';

export const searchVisitorByPhone = async (phone) => {
    const { data, error } = await supabase.from('visitors').select('*').ilike('phone', `%${phone}%`).limit(5);
    if (error) throw error;
    return data || [];
};

export const getVisitorByPhone = async (phone) => {
    const { data, error } = await supabase.from('visitors').select('*, cars(*)').eq('phone', phone).single();
    if (error && error.code !== 'PGRST116') throw error;
    return data;
};

export const createVisitor = async (visitorData) => {
    const mappedData = {
        name: visitorData.name,
        phone: visitorData.phone,
        email: visitorData.email,
        valet_company_id: visitorData.companyId || visitorData.valet_company_id,
        ...visitorData
    };
    const { data, error } = await supabase.from('visitors').insert(mappedData).select().single();
    if (error) throw error;
    return data;
};
