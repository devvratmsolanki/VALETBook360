// Centralized webhook service — routes through Supabase Edge Function
// The edge function handles Yeti's two-step auth (API Key → JWT → Bearer) server-side
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;

const isConfigured = () => SUPABASE_URL && SUPABASE_ANON_KEY;

const sendTemplate = async (phone, templateName, components) => {
    if (!isConfigured()) {
        console.warn('[WhatsApp] Supabase not configured, skipping notification');
        return;
    }
    if (!phone) {
        console.warn('[WhatsApp] No phone number provided, skipping');
        return;
    }

    const cleanPhone = phone.replace(/\D/g, '').trim();
    console.log(`[WhatsApp] Sending "${templateName}" to ${cleanPhone} via Edge Function...`);

    try {
        const response = await fetch(`${SUPABASE_URL}/functions/v1/send-whatsapp`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
            },
            body: JSON.stringify({
                phone: cleanPhone,
                templateName,
                components,
            }),
        });

        const data = await response.json();

        if (response.ok && data.success) {
            console.log(`[WhatsApp] SUCCESS! Template "${templateName}" sent to ${cleanPhone}`);
            return data;
        }

        console.error(`[WhatsApp] Failed (${response.status}):`, JSON.stringify(data, null, 2));
        return data;
    } catch (err) {
        console.error(`[WhatsApp] Network error:`, err.message);
    }
};

// ─── Workflow 1: Car Parked ───
export const sendCarParked = ({ guest_name, phone, car_number, parking_slot, driver_name, driver_id, company_name, transaction_id }) => {
    const timeStr = new Date().toLocaleString('en-IN', { hour12: false });

    return sendTemplate(phone, 'car_parked_notification', [
        {
            type: "body",
            parameters: [
                { type: "text", text: guest_name || 'Valued Guest' },
                { type: "text", text: parking_slot || 'Main Parking' },
                { type: "text", text: company_name || 'VALETBook360' },
                { type: "text", text: timeStr },
                { type: "text", text: driver_name || 'Valet Agent' },
                { type: "text", text: driver_id || 'VT001' },
                { type: "text", text: company_name || 'Valet Support' }
            ]
        },
        {
            type: "button",
            sub_type: "url",
            index: "0",
            parameters: [
                { type: "text", text: transaction_id || 'view' }
            ]
        }
    ]);
};

// ─── Workflow 2: Request Received ───
export const sendRequestReceived = ({ phone, car_number }) => {
    return sendTemplate(phone, 'received_request_notification', [
        {
            type: "body",
            parameters: [
                { type: "text", text: car_number || 'Your Vehicle' }
            ]
        }
    ]);
};

// ─── Workflow 3: Driver Assigned for Retrieval ───
export const sendDriverAssigned = ({ phone, driver_name, driver_id, location_name, eta_minutes }) => {
    const now = new Date();
    const eta = eta_minutes || 5;
    const etaTime = new Date(now.getTime() + eta * 60000);
    const etaStr = `${etaTime.getHours().toString().padStart(2, '0')}:${etaTime.getMinutes().toString().padStart(2, '0')} (${eta} mins)`;

    return sendTemplate(phone, 'driver_assigned_notification', [
        {
            type: "body",
            parameters: [
                { type: "text", text: driver_name || 'Valet Agent' },
                { type: "text", text: driver_id || 'VT001' },
                { type: "text", text: location_name || 'Valet Exit' },
                { type: "text", text: etaStr }
            ]
        }
    ]);
};

// ─── Workflow 4: Car Ready ───
export const sendCarReady = ({ phone, car_number, location_name }) => {
    return sendTemplate(phone, 'car_ready_notification', [
        {
            type: "body",
            parameters: [
                { type: "text", text: car_number || 'Your Vehicle' },
                { type: "text", text: location_name || 'Valet Pick-up' }
            ]
        }
    ]);
};

// ─── Workflow 5: Car Delivered ───
export const sendCarDelivered = ({ phone, car_number, company_name }) => {
    const timeStr = new Date().toLocaleString('en-IN', { hour12: false });
    return sendTemplate(phone, 'car_delivered_thankyou', [
        {
            type: "body",
            parameters: [
                { type: "text", text: car_number || 'Your Vehicle' },
                { type: "text", text: timeStr }
            ]
        }
    ]);
};

export default { sendCarParked, sendRequestReceived, sendDriverAssigned, sendCarReady, sendCarDelivered };
