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

export const createSlot = async (slot) => {
    const { data, error } = await supabase
        .from('key_slots')
        .insert(slot)
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

export const bulkGenerateSlots = async (locationId, prefix, count, startFrom = 1) => {
    const slots = [];
    for (let i = 0; i < count; i++) {
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
    const { data: existingSlots, error: fetchErr } = await supabase
        .from('key_slots')
        .select('id, sort_order')
        .eq('location_id', locationId)
        .order('sort_order', { ascending: true });

    if (fetchErr) throw fetchErr;

    const currentCount = existingSlots.length;

    if (targetCount > currentCount) {
        // Need to add slots
        const toAdd = targetCount - currentCount;
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
    } else if (targetCount < currentCount) {
        // Need to remove slots (from the end)
        const toRemove = currentCount - targetCount;
        const idsToRemove = existingSlots.slice(-toRemove).map(s => s.id);
        const { error: deleteErr } = await supabase.from('key_slots').delete().in('id', idsToRemove);
        if (deleteErr) throw deleteErr;
    }
};
