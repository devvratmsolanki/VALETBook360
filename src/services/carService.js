import { supabase } from '../lib/supabase';

export const findCarByNumber = async (carNumber) => {
    const { data, error } = await supabase.from('cars').select('*').eq('car_number', carNumber).single();
    if (error && error.code !== 'PGRST116') throw error;
    return data;
};

export const createCar = async (car) => {
    const { data, error } = await supabase.from('cars').insert(car).select().single();
    if (error) throw error;
    return data;
};

export const getCarsByVisitor = async (visitorId) => {
    const { data, error } = await supabase.from('cars').select('*').eq('visitor_id', visitorId);
    if (error) throw error;
    return data || [];
};
