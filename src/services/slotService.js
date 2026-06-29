import { supabase } from '../lib/supabase';

export const getSlotsByLocation = async (locationId) => {
    const { data, error } = await supabase
        .from('key_slots')
        .select('*')
        .eq('location_id', locationId)
        .order('sort_order', { ascending: true })
        .order('slot_name', { ascending: true });
    if (error) throw error;
    return data || [];
};

/**
 * Returns the ORDERED list of slot names for a location: custom key_slots
 * (by sort_order) if any exist, otherwise numeric "1".."key_capacity".
 * Mirrors the allocation logic in transactionService.getNextAvailableKeySlot
 * so the operator grid and the auto-default agree on the pool.
 */
export const getLocationSlotNames = async (locationId) => {
    if (!locationId) return [];
    const slots = await getSlotsByLocation(locationId);
    if (slots && slots.length > 0) return slots.map(s => s.slot_name);

    const { data: loc, error } = await supabase
        .from('locations')
        .select('key_capacity')
        .eq('id', locationId)
        .single();
    if (error) throw error;
    const capacity = loc?.key_capacity || 0;
    return Array.from({ length: capacity }, (_, i) => (i + 1).toString());
};

export const createSlot = async (slotData) => {
    const mapped = {
        location_id: slotData.locationId || slotData.location_id,
        slot_name: slotData.slotName || slotData.slot_name,
        sort_order: slotData.sortOrder || slotData.sort_order,
    };
    const { data, error } = await supabase
        .from('key_slots')
        .insert(mapped)
        .select()
        .single();
    if (error) throw error;
    return data;
};

export const updateSlotName = async (id, slot_name) => {
    const { data, error } = await supabase
        .from('key_slots')
        .update({ slot_name })
        .eq('id', id)
        .select()
        .single();
    if (error) throw error;
    return data;
};

export const deleteSlot = async (id) => {
    const { error } = await supabase
        .from('key_slots')
        .delete()
        .eq('id', id);
    if (error) throw error;
};

const MAX_BULK_SLOTS = 500;

export const bulkGenerateSlots = async (locationId, prefix, count, startFrom = 1) => {
    const n = Math.max(0, Math.min(MAX_BULK_SLOTS, Math.floor(Number(count) || 0)));
    if (n === 0) return [];
    const slots = [];
    for (let i = 0; i < n; i++) {
        slots.push({
            location_id: locationId,
            slot_name: `${prefix}${startFrom + i}`,
            sort_order: startFrom + i
        });
    }
    const { data, error } = await supabase
        .from('key_slots')
        .insert(slots)
        .select();
    if (error) throw error;
    return data;
};

export const clearAllSlots = async (locationId) => {
    const { error } = await supabase
        .from('key_slots')
        .delete()
        .eq('location_id', locationId);
    if (error) throw error;
};

export const syncSlotsWithCapacity = async (locationId, targetCount) => {
    const target = Math.max(0, Math.min(MAX_BULK_SLOTS, Math.floor(Number(targetCount) || 0)));
    const { data: existingSlots, error: fetchErr } = await supabase
        .from('key_slots')
        .select('id, sort_order')
        .eq('location_id', locationId)
        .order('sort_order', { ascending: true });

    if (fetchErr) throw fetchErr;

    const currentCount = existingSlots.length;

    if (target > currentCount) {
        const toAdd = target - currentCount;
        const slotsToAdd = [];
        for (let i = 0; i < toAdd; i++) {
            slotsToAdd.push({
                location_id: locationId,
                slot_name: (currentCount + i + 1).toString(),
                sort_order: currentCount + i + 1
            });
        }
        const { error: insertErr } = await supabase.from('key_slots').insert(slotsToAdd);
        if (insertErr) throw insertErr;
    } else if (target < currentCount) {
        const toRemove = currentCount - target;
        const idsToRemove = existingSlots.slice(-toRemove).map(s => s.id);
        const { error: deleteErr } = await supabase.from('key_slots').delete().in('id', idsToRemove);
        if (deleteErr) throw deleteErr;
    }
};
