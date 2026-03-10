import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

let supabase;

if (supabaseUrl && supabaseAnonKey && supabaseUrl !== 'your_supabase_url_here') {
    supabase = createClient(supabaseUrl, supabaseAnonKey, {
        auth: {
            // Bypass navigator lock to prevent NavigatorLockAcquireTimeoutError
            lock: async (name, acquireTimeout, fn) => {
                return await fn();
            },
            persistSession: true,
            autoRefreshToken: true,
        },
    });
} else {
    console.warn('Supabase not configured. Running in demo mode.');
    const mockResp = { data: null, error: null };
    const mockQuery = () => ({
        select: () => mockQuery(),
        insert: () => mockQuery(),
        update: () => mockQuery(),
        delete: () => mockQuery(),
        eq: () => mockQuery(),
        ilike: () => mockQuery(),
        in: () => mockQuery(),
        inFilter: () => mockQuery(),
        order: () => mockQuery(),
        limit: () => mockQuery(),
        single: () => Promise.resolve(mockResp),
        maybeSingle: () => Promise.resolve(mockResp),
        then: (cb) => Promise.resolve(mockResp).then(cb),
    });
    supabase = {
        from: () => mockQuery(),
        auth: {
            getSession: () => Promise.resolve({ data: { session: null } }),
            onAuthStateChange: (cb) => {
                setTimeout(() => cb('INITIAL_SESSION', null), 0);
                return { data: { subscription: { unsubscribe: () => { } } } };
            },
            signInWithPassword: () => Promise.reject(new Error('Supabase not configured. Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to .env')),
            signOut: () => Promise.resolve(),
        },
        channel: () => ({
            on: function () { return this; },
            subscribe: function () { return { unsubscribe: () => { } }; },
        }),
    };
}

export { supabase };
