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

export const createVisitor = async (visitor) => {
    const { data, error } = await supabase.from('visitors').insert(visitor).select().single();
    if (error) throw error;
    return data;
};
