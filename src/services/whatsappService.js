import { supabase } from '../lib/supabase';

export const getWhatsAppLogs = async (limit = 100) => {
    const { data, error } = await supabase.from('whatsapp_logs').select('*, visitors:visitor_id(name, phone), valet_transactions:transaction_id(status)').order('created_at', { ascending: false }).limit(limit);
    if (error) throw error;
    return data || [];
};

export const getLogsByPhone = async (phone) => {
    const { data, error } = await supabase.from('whatsapp_logs').select('*').eq('phone', phone).order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
};
