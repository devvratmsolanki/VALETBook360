import { supabase } from '../lib/supabase';

// Resolve the drivers row for a logged-in driver user.
// Migration 20260520_link_drivers_to_users.sql added user_id and email columns;
// both must be present for this lookup to succeed.
//
// The legacy "match on name within company" fallback was removed: it allowed
// any new auth account whose name happened to match an existing driver to
// inherit that driver's tasks (driver impersonation).
// eslint-disable-next-line no-unused-vars
export const getDriverForUser = async ({ userId, email, name, companyId }) => {
    if (userId) {
        const { data } = await supabase
            .from('drivers')
            .select('id, name, staff_id, valet_company_id, location_id')
            .eq('user_id', userId)
            .maybeSingle();
        if (data) return data;
    }

    if (email) {
        const { data } = await supabase
            .from('drivers')
            .select('id, name, staff_id, valet_company_id, location_id')
            .ilike('email', email)
            .maybeSingle();
        if (data) return data;
    }

    return null;
};

export const getDriversByCompany = async (companyId) => {
    const { data, error } = await supabase.from('drivers').select('*, contracts(locations:location_id(name))').eq('valet_company_id', companyId).order('staff_id', { ascending: true });
    if (error) throw error;
    return data || [];
};

export const getDrivers = async () => {
    const { data, error } = await supabase.from('drivers').select('*, valet_companies:valet_company_id(company_name)').order('staff_id', { ascending: true });
    if (error) throw error;
    return data || [];
};

export const createDriver = async (driverData) => {
    const mapped = {
        valet_company_id: driverData.companyId || driverData.valet_company_id,
        name: driverData.name,
        phone: driverData.phone,
        email: driverData.email,
        staff_id: driverData.staffId || driverData.staff_id,
        location_id: driverData.locationId || driverData.location_id || null,
        user_id: driverData.userId || driverData.user_id || null,
        license_number: driverData.license_number || driverData.licenseNumber || null,
        active: driverData.active ?? true,
    };
    const { data, error } = await supabase.from('drivers').insert(mapped).select().single();
    if (error) throw error;
    return data;
};

export const updateDriver = async (id, driverData) => {
    const mapped = {};
    if (driverData.name !== undefined) mapped.name = driverData.name;
    if (driverData.phone !== undefined) mapped.phone = driverData.phone;
    if (driverData.email !== undefined) mapped.email = driverData.email;
    if (driverData.staff_id !== undefined || driverData.staffId !== undefined) {
        mapped.staff_id = driverData.staffId || driverData.staff_id;
    }
    if (driverData.location_id !== undefined || driverData.locationId !== undefined) {
        mapped.location_id = driverData.locationId || driverData.location_id;
    }
    if (driverData.active !== undefined) mapped.active = driverData.active;
    const { data, error } = await supabase.from('drivers').update(mapped).eq('id', id).select().single();
    if (error) throw error;
    return data;
};

export const toggleDriverActive = async (id, active) => updateDriver(id, { active });

// Deletes the drivers row. If the driver had a linked login (user_id),
// the auth user's profile is also removed so they can no longer sign in
// as a driver. The auth.users record itself persists (would need an
// admin-only edge function to remove).
//
// Migration 20260520 set the FK on valet_transactions to ON DELETE SET NULL,
// so the DB transparently nulls the driver reference on historical rows when
// the driver is deleted. We previously did this manually in JS, which was
// non-atomic — if the row delete failed after the nulling, historical audit
// data was already destroyed. Trust the FK constraint instead.
export const deleteDriver = async (id) => {
    const { data, error: fetchErr } = await supabase
        .from('drivers')
        .select('user_id')
        .eq('id', id)
        .maybeSingle();
    const missingCol = fetchErr && /user_id|column/i.test(fetchErr.message || '');
    if (fetchErr && !missingCol) throw fetchErr;
    const userId = data?.user_id || null;

    const { error: delErr } = await supabase.from('drivers').delete().eq('id', id);
    if (delErr) throw delErr;

    if (userId) {
        await supabase.from('users').delete().eq('id', userId);
    }
};
