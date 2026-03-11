import { supabase } from '../lib/supabase';

/**
 * Full BRD Status Lifecycle:
 * waiting_for_driver → parked → key_in → requested → driver_assigned → en_route → arrived → delivered (or cancelled)
 */

export const STATUS_FLOW = [
    'waiting_for_driver', 'parked', 'key_in', 'requested',
    'driver_assigned', 'en_route', 'arrived', 'delivered', 'cancelled'
];

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
        .in('status', ['waiting_for_driver', 'parked', 'key_in', 'requested', 'driver_assigned', 'en_route', 'arrived', 'delivered'])
        .order('created_at', { ascending: false });
    if (companyId) query = query.eq('valet_company_id', companyId);
    const { data, error } = await query;
    if (error) throw error;
    return data || [];
};

export const createTransaction = async (txData) => {
    // Map camelCase to snake_case for database
    const mappedData = {
        valet_company_id: txData.companyId || txData.valet_company_id,
        location_id: txData.locationId || txData.location_id,
        visitor_id: txData.visitorId || txData.visitor_id,
        car_id: txData.carId || txData.car_id,
        status: txData.status || 'waiting_for_driver',
        parked_by_driver_id: txData.parkedByDriverId || txData.parked_by_driver_id,
        key_code: txData.keyCode || txData.key_code,
        parking_slot: txData.parkingSlot || txData.parking_slot,
        ...txData // Include any other fields already in snake_case
    };

    const { data, error } = await supabase
        .from('valet_transactions')
        .insert(mappedData)
        .select()
        .single();
    if (error) throw error;
    return data;
};

export const updateTransactionStatus = async (id, status, extraFields = {}) => {
    const timestampField = {
        requested: 'requested_at',
        arrived: 'ready_at',
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

/**
 * Confirm key receipt — Operator acknowledges physical key handover
 * parked → key_in
 */
export const confirmKeyIn = async (id) => {
    return updateTransactionStatus(id, 'key_in');
};

/**
 * Assign driver for retrieval — sets driver_assigned status
 */
export const assignDriverForRetrieval = async (id, driverId, etaMinutes = 8) => {
    const estimatedTime = new Date(Date.now() + etaMinutes * 60 * 1000).toISOString();
    return updateTransactionStatus(id, 'driver_assigned', {
        retrieved_by_driver_id: driverId,
        eta_minutes: etaMinutes,
        estimated_delivery_time: estimatedTime,
    });
};

/**
 * Mark driver en route (driver has picked up keys and is going to vehicle)
 */
export const markEnRoute = async (id) => {
    return updateTransactionStatus(id, 'en_route');
};

/**
 * Mark driver arrived at pickup point
 */
export const markArrived = async (id) => {
    return updateTransactionStatus(id, 'arrived');
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

    // Single-pass aggregation
    const counts = { total: all.length, active: 0, waiting: 0, parked: 0, requested: 0, ready: 0, delivered: 0, today: 0 };
    for (const t of all) {
        const s = t.status;
        if (s === 'waiting_for_driver') { counts.waiting++; counts.active++; }
        else if (s === 'parked' || s === 'key_in') { counts.parked++; counts.active++; }
        else if (s === 'requested' || s === 'driver_assigned' || s === 'en_route') { counts.requested++; counts.active++; }
        else if (s === 'arrived') { counts.ready++; counts.active++; }
        else if (s === 'delivered') counts.delivered++;
        if (t.created_at?.startsWith(today)) counts.today++;
    }
    return counts;
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

    // 2. Fetch occupied slots from active transactions (whitelist of visible statuses)
    const { data: txs, error: txErr } = await supabase
        .from('valet_transactions')
        .select('key_code')
        .eq('location_id', locationId)
        .in('status', ['waiting_for_driver', 'parked', 'key_in', 'requested', 'driver_assigned', 'en_route', 'arrived']);
    if (txErr) throw txErr;

    const occupied = new Set(txs.map(t => t.key_code).filter(Boolean));

    // 3. Logic choice: Custom Slots vs Numerical Capacity
    if (slots && slots.length > 0) {
        for (const slot of slots) {
            if (!occupied.has(slot.slot_name)) return slot.slot_name;
        }
        return null;
    } else {
        const { data: loc, error: locErr } = await supabase.from('locations').select('key_capacity').eq('id', locationId).single();
        if (locErr) throw locErr;
        const capacity = loc?.key_capacity || 0;
        if (capacity <= 0) return null;

        for (let i = 1; i <= capacity; i++) {
            const numStr = i.toString();
            if (!occupied.has(numStr)) return numStr;
        }
        return null;
    }
};

export const getDriverPerformanceStats = async (_companyId = null) => {
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
