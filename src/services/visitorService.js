import { supabase } from '../lib/supabase';

// Escape LIKE/ILIKE wildcards in user-supplied input. Without this, a user
// who types `%` into the phone search would match every visitor in the DB.
const escapeLike = (s) => String(s || '').replace(/[\\%_]/g, (m) => '\\' + m);

export const searchVisitorByPhone = async (phone) => {
    const safe = escapeLike(phone);
    if (!safe) return [];
    const { data, error } = await supabase.from('visitors').select('*').ilike('phone', `%${safe}%`).limit(5);
    if (error) throw error;
    return data || [];
};

export const getVisitorByPhone = async (phone) => {
    const { data, error } = await supabase.from('visitors').select('*, cars(*)').eq('phone', phone).single();
    if (error && error.code !== 'PGRST116') throw error;
    return data;
};

export const createVisitor = async (visitorData) => {
    const mapped = {
        name: visitorData.name,
        phone: visitorData.phone,
        email: visitorData.email,
        valet_company_id: visitorData.companyId || visitorData.valet_company_id,
    };
    const { data, error } = await supabase.from('visitors').insert(mapped).select().single();
    if (error) throw error;
    return data;
};
