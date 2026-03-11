import { supabase } from '../lib/supabase';

export const findCarByNumber = async (carNumber) => {
    const { data, error } = await supabase.from('cars').select('*').eq('car_number', carNumber).single();
    if (error && error.code !== 'PGRST116') throw error;
    return data;
};

export const createCar = async (carData) => {
    const mappedData = {
        car_number: carData.carNumber || carData.car_number,
        make: carData.make,
        model: carData.model,
        color: carData.color,
        ...carData
    };
    const { data, error } = await supabase.from('cars').insert(mappedData).select().single();
    if (error) throw error;
    return data;
};

export const getCarsByVisitor = async (visitorId) => {
    const { data, error } = await supabase.from('cars').select('*').eq('visitor_id', visitorId);
    if (error) throw error;
    return data || [];
};
