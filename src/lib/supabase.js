import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

let supabase;

// `isMockClient` is exported so the UI can render an unmistakable banner when
// the app boots without real credentials. Otherwise a demo-mode deploy looks
// indistinguishable from a broken production deploy.
export const isMockClient = !(supabaseUrl && supabaseAnonKey && supabaseUrl !== 'your_supabase_url_here');

if (!isMockClient) {
    supabase = createClient(supabaseUrl, supabaseAnonKey, {
        auth: {
            storage: typeof window !== 'undefined' ? window.sessionStorage : undefined,
            persistSession: true,
            autoRefreshToken: true,
        },
    });
} else {
    // In production builds we want this to be loud — silent demo-mode in
    // production was making real outages look like user error. The console
    // warning stays for devs; the runtime banner is rendered from App.jsx.
    if (import.meta.env.PROD) {
        console.error('[Supabase] Missing VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY in production build. Running in demo mode.');
    } else {
        console.warn('Supabase not configured. Running in demo mode.');
    }
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
