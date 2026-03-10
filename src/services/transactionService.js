import { supabase } from '../lib/supabase';

export const getTransactions = async (companyId = null) => {
    let query = supabase
        .from('valet_transactions')
        .select(`
            *,
            visitors(id, name, phone),
            cars(id, car_number, make, model, color),
            parked_driver:parked_by_driver_id(id, name, phone),
            retrieved_driver:retrieved_by_driver_id(id, name, phone),
            locations:location_id(id, name)
        `)
        .order('created_at', { ascending: false });
    if (companyId) query = query.eq('valet_company_id', companyId);
    const { data, error } = await query;
    if (error) throw error;
    return data || [];
};

export const getActiveTransactions = async (companyId = null) => {
    let query = supabase
        .from('valet_transactions')
        .select(`
            *,
            visitors(id, name, phone),
            cars(id, car_number, make, model, color),
            parked_driver:parked_by_driver_id(id, name, phone),
            retrieved_driver:retrieved_by_driver_id(id, name, phone),
            locations:location_id(id, name)
        `)
        .in('status', ['parked', 'requested', 'ready', 'delivered'])
        .order('created_at', { ascending: false });
    if (companyId) query = query.eq('valet_company_id', companyId);
    const { data, error } = await query;
    if (error) throw error;
    return data || [];
};

export const createTransaction = async (txData) => {
    const { data, error } = await supabase
        .from('valet_transactions')
        .insert(txData)
        .select()
        .single();
    if (error) throw error;
    return data;
};

export const updateTransactionStatus = async (id, status, extraFields = {}) => {
    const timestampField = {
        requested: 'requested_at',
        ready: 'ready_at',
        delivered: 'delivered_at',
    };
    const update = {
        status,
        updated_at: new Date().toISOString(),
        ...extraFields,
    };
    if (timestampField[status]) update[timestampField[status]] = new Date().toISOString();
    if (status === 'delivered') update.actual_delivery_time = new Date().toISOString();

    const { data, error } = await supabase
        .from('valet_transactions')
        .update(update)
        .eq('id', id)
        .select()
        .single();
    if (error) throw error;
    return data;
};

export const assignDriverForRetrieval = async (id, driverId, etaMinutes = 8) => {
    const estimatedTime = new Date(Date.now() + etaMinutes * 60 * 1000).toISOString();
    return updateTransactionStatus(id, 'requested', {
        retrieved_by_driver_id: driverId,
        eta_minutes: etaMinutes,
        estimated_delivery_time: estimatedTime,
    });
};

export const subscribeToTransactions = (callback) => {
    return supabase
        .channel('valet_transactions_realtime')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'valet_transactions' }, (payload) => callback(payload))
        .subscribe();
};

export const getTransactionStats = async (companyId = null) => {
    let query = supabase.from('valet_transactions').select('status, created_at');
    if (companyId) query = query.eq('valet_company_id', companyId);
    const { data, error } = await query;
    if (error) throw error;
    const all = data || [];
    const today = new Date().toISOString().split('T')[0];
    return {
        total: all.length,
        active: all.filter(t => !['delivered', 'cancelled'].includes(t.status)).length,
        parked: all.filter(t => t.status === 'parked').length,
        requested: all.filter(t => t.status === 'requested').length,
        ready: all.filter(t => t.status === 'ready').length,
        delivered: all.filter(t => t.status === 'delivered').length,
        today: all.filter(t => t.created_at?.startsWith(today)).length,
    };
};

export const getNextAvailableKeySlot = async (locationId) => {
    // 1. Fetch custom slots for this location
    const { data: slots, error: slotErr } = await supabase
        .from('key_slots')
        .select('slot_name')
        .eq('location_id', locationId)
        .order('sort_order', { ascending: true })
        .order('slot_name', { ascending: true });

    if (slotErr) throw slotErr;

    // 2. Fetch occupied slots from active transactions
    const { data: txs, error: txErr } = await supabase
        .from('valet_transactions')
        .select('key_code')
        .eq('location_id', locationId)
        .not('status', 'eq', 'delivered')
        .not('status', 'eq', 'cancelled');
    if (txErr) throw txErr;

    const occupied = new Set(txs.map(t => t.key_code).filter(Boolean));

    // 3. Logic choice: Custom Slots vs Numerical Capacity
    if (slots && slots.length > 0) {
        // Use custom slots from key_slots table
        for (const slot of slots) {
            if (!occupied.has(slot.slot_name)) return slot.slot_name;
        }
        return null; // All custom slots full
    } else {
        // Fallback: Use legacy numerical capacity
        const { data: loc, error: locErr } = await supabase.from('locations').select('key_capacity').eq('id', locationId).single();
        if (locErr) throw locErr;
        const capacity = loc?.key_capacity || 0;
        if (capacity <= 0) return null;

        for (let i = 1; i <= capacity; i++) {
            const numStr = i.toString();
            if (!occupied.has(numStr)) return numStr;
        }
        return null; // Numerical capacity full
    }
};

export const getDriverPerformanceStats = async (companyId = null) => {
    const { data, error } = await supabase
        .from('valet_transactions')
        .select(`
            id, status, created_at, eta_minutes,
            estimated_delivery_time, actual_delivery_time,
            parked_by_driver_id, retrieved_by_driver_id,
            locations:location_id(id, name),
            parked_driver:parked_by_driver_id(id, name),
            retrieved_driver:retrieved_by_driver_id(id, name)
        `)
        .order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
};
