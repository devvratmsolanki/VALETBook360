import { supabase } from '../lib/supabase';
import { parseUTC } from '../lib/utils';

/**
 * Full BRD Status Lifecycle:
 * waiting_for_driver → parked → key_in → requested → driver_assigned → en_route → arrived → delivered (or cancelled)
 */

export const STATUS_FLOW = [
    'waiting_for_driver', 'parked', 'key_in', 'requested',
    'driver_assigned', 'en_route', 'arrived', 'delivered', 'cancelled'
];

// Legal successor states from each status. Used to prevent illegal transitions
// like delivered → parked. cancelled is reachable from any active state.
const LEGAL_TRANSITIONS = {
    waiting_for_driver: ['parked', 'key_in', 'cancelled'],
    parked: ['key_in', 'requested', 'cancelled'],
    key_in: ['requested', 'cancelled'],
    requested: ['driver_assigned', 'cancelled'],
    driver_assigned: ['en_route', 'cancelled'],
    en_route: ['arrived', 'cancelled'],
    arrived: ['delivered', 'cancelled'],
    delivered: [],
    cancelled: [],
};

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
    // Without an explicit company filter this would return every company's
    // active transactions (RLS permitting), so callers that forget to pass
    // companyId would leak cross-tenant data. Refuse the unscoped call rather
    // than silently fetching everything.
    if (!companyId) return [];
    const { data, error } = await supabase
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
        .eq('valet_company_id', companyId)
        .order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
};

// Whitelist of columns the client is allowed to set on insert. Any field
// outside this list (status, valet_company_id overrides, etc.) is silently
// discarded — this prevents callers from injecting privileged fields by
// passing snake_case names that the previous `...txData` spread would have
// applied verbatim.
const TRANSACTION_INSERT_FIELDS = new Set([
    'valet_company_id', 'location_id', 'visitor_id', 'car_id',
    'parked_by_driver_id', 'key_code', 'parking_slot',
    'payment_status', 'parking_remarks', 'parking_coordinates',
    'parking_map_link', 'parking_photos', 'photo_urls',
]);

export const createTransaction = async (txData) => {
    const mapped = {
        valet_company_id: txData.companyId || txData.valet_company_id,
        location_id: txData.locationId || txData.location_id,
        visitor_id: txData.visitorId || txData.visitor_id,
        car_id: txData.carId || txData.car_id,
        parked_by_driver_id: txData.parkedByDriverId || txData.parked_by_driver_id,
        key_code: txData.keyCode || txData.key_code,
        parking_slot: txData.parkingSlot || txData.parking_slot,
    };
    for (const [k, v] of Object.entries(txData)) {
        if (TRANSACTION_INSERT_FIELDS.has(k) && mapped[k] === undefined) mapped[k] = v;
    }
    // status is intentionally forced — callers must not bypass the state
    // machine by inserting a transaction already at `delivered`.
    mapped.status = 'waiting_for_driver';

    const { data, error } = await supabase
        .from('valet_transactions')
        .insert(mapped)
        .select()
        .single();
    if (error) throw error;
    return data;
};

// Whitelist of fields callers may update alongside a status change.
const TRANSACTION_UPDATE_FIELDS = new Set([
    'parked_by_driver_id', 'retrieved_by_driver_id', 'key_code', 'parking_slot',
    'eta_minutes', 'estimated_delivery_time', 'pickup_location',
    'payment_status', 'parking_remarks', 'parking_coordinates',
    'parking_map_link', 'parking_photos', 'photo_urls',
]);

export const updateTransactionStatus = async (id, status, extraFields = {}) => {
    if (!STATUS_FLOW.includes(status)) {
        throw new Error(`Invalid status: ${status}`);
    }

    // Validate the transition against the current DB state. Client-side
    // only — for tamper-proof enforcement this should also run as a
    // Postgres trigger, but checking here at least catches honest bugs
    // (like writing the non-existent `'ready'` status) before they hit
    // the DB and orphan transactions.
    const { data: current, error: fetchErr } = await supabase
        .from('valet_transactions')
        .select('status')
        .eq('id', id)
        .single();
    if (fetchErr) throw fetchErr;
    const allowed = LEGAL_TRANSITIONS[current.status] || [];
    if (current.status !== status && !allowed.includes(status)) {
        throw new Error(`Illegal transition: ${current.status} → ${status}`);
    }

    const timestampField = {
        requested: 'requested_at',
        arrived: 'ready_at',
        delivered: 'delivered_at',
    };
    const update = { status, updated_at: new Date().toISOString() };
    for (const [k, v] of Object.entries(extraFields)) {
        if (TRANSACTION_UPDATE_FIELDS.has(k)) update[k] = v;
    }
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
 * Assign driver for retrieval — sets driver_assigned status.
 * extras may include pickup_location so it lands in the same write and
 * Realtime subscribers don't briefly see a driver_assigned record without it.
 */
export const assignDriverForRetrieval = async (id, driverId, etaMinutes = 8, extras = {}) => {
    const estimatedTime = new Date(Date.now() + etaMinutes * 60 * 1000).toISOString();
    return updateTransactionStatus(id, 'driver_assigned', {
        retrieved_by_driver_id: driverId,
        eta_minutes: etaMinutes,
        estimated_delivery_time: estimatedTime,
        ...extras,
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

    // "Today" is interpreted in the user's local timezone using parseUTC to
    // correctly anchor the DB UTC timestamp. The previous `startsWith(today)`
    // compared the local UTC-date string against the raw DB string, which
    // misclassified timestamps near the day boundary.
    const startOfToday = new Date();
    startOfToday.setHours(0, 0, 0, 0);
    const startOfTodayMs = startOfToday.getTime();

    const counts = { total: all.length, active: 0, waiting: 0, parked: 0, requested: 0, ready: 0, delivered: 0, today: 0 };
    for (const t of all) {
        const s = t.status;
        if (s === 'waiting_for_driver') { counts.waiting++; counts.active++; }
        else if (s === 'parked' || s === 'key_in') { counts.parked++; counts.active++; }
        else if (s === 'requested' || s === 'driver_assigned' || s === 'en_route') { counts.requested++; counts.active++; }
        else if (s === 'arrived') { counts.ready++; counts.active++; }
        else if (s === 'delivered') counts.delivered++;
        const created = parseUTC(t.created_at);
        if (created && created.getTime() >= startOfTodayMs) counts.today++;
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

export const getDriverPerformanceStats = async (companyId = null) => {
    let query = supabase
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
    if (companyId) query = query.eq('valet_company_id', companyId);
    const { data, error } = await query;
    if (error) throw error;
    return data || [];
};
