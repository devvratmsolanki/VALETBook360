import { createContext, useContext, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

const AuthContext = createContext({});

export const useAuth = () => useContext(AuthContext);

export const AuthProvider = ({ children }) => {
    const [user, setUser] = useState(null);
    const [profile, setProfile] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        let mounted = true;

        const initAuth = async () => {
            try {
                const { data: { session } } = await supabase.auth.getSession();
                console.log('[Auth] Initial session:', session ? 'found' : 'none');
                if (session?.user && mounted) {
                    setUser(session.user);
                    await fetchProfile(session.user);
                }
            } catch (err) {
                console.error('[Auth] getSession error:', err);
            } finally {
                if (mounted) setLoading(false);
            }
        };

        initAuth();

        const { data: { subscription } } = supabase.auth.onAuthStateChange(
            async (event, session) => {
                console.log('[Auth] State changed:', event, session ? 'has session' : 'no session');
                if (!mounted) return;

                if (event === 'SIGNED_IN' && session?.user) {
                    // Stay in loading state until profile is fetched — otherwise role
                    // defaults to 'valet' during the gap and AuthGate routes the user
                    // to the wrong dashboard (e.g. drivers landing on /operator).
                    setLoading(true);
                    setUser(session.user);
                    await fetchProfile(session.user);
                    if (mounted) setLoading(false);
                } else if (event === 'SIGNED_OUT') {
                    setUser(null);
                    setProfile(null);
                    setLoading(false);
                }
            }
        );

        return () => {
            mounted = false;
            subscription.unsubscribe();
        };
    }, []);

    const fetchProfile = async (authUser) => {
        const userId = authUser.id;
        const email = authUser.email;
        try {
            console.log('[Auth] Fetching profile for:', userId);
            let { data, error } = await supabase
                .from('users')
                .select('*, valet_companies(company_name, phone), location:location_id(id, name)')
                .eq('id', userId)
                .single();

            if (error) {
                console.warn('[Auth] Detailed fetch failed (might be missing location_id column). Trying fallback...');
                const { data: fallbackData, error: fallbackError } = await supabase
                    .from('users')
                    .select('*, valet_companies(company_name, phone)')
                    .eq('id', userId)
                    .single();

                if (fallbackError) throw fallbackError;
                data = fallbackData;
            }

            if (!data) {
                console.warn('[Auth] No profile found. Auto-creating...');
                await autoCreateProfile(userId, email);
            } else {
                console.log('[Auth] Profile loaded, role:', data?.role);
                setProfile(data);
            }
        } catch (err) {
            console.error('[Auth] Profile fetch exception:', err);
            await autoCreateProfile(userId, email);
        }
    };

    const autoCreateProfile = async (userId, email) => {
        try {
            // Check if any admin already exists — if so, this user MUST be valet.
            // The previous "first user becomes admin" path was a TOCTOU: two concurrent
            // signups on a fresh install could both read 0 rows and both insert as admin.
            // We now check specifically for an existing admin row and rely on a unique
            // constraint on (role='admin') at the DB level for true atomicity. Without
            // that constraint, the first admin must be promoted manually via the SQL editor.
            const { data: existingAdmins } = await supabase
                .from('users')
                .select('id')
                .eq('role', 'admin')
                .limit(1);

            const isFirstUser = !existingAdmins || existingAdmins.length === 0;
            const role = isFirstUser ? 'admin' : 'valet';

            console.log('[Auth] Auto-creating profile, role:', role, '(first admin:', isFirstUser, ')');

            const { data: newProfile, error: insertError } = await supabase
                .from('users')
                .insert({
                    id: userId,
                    email: email,
                    name: email.split('@')[0],
                    role: role,
                })
                .select('*, valet_companies(company_name)')
                .single();

            if (insertError) {
                console.error('[Auth] Auto-create failed:', insertError.message);
                // Fallback: set a minimal profile so routing works. Always default to the
                // least-privileged role; never silently grant admin on insert failure.
                setProfile({ id: userId, email, role: 'valet', name: email.split('@')[0] });
            } else {
                console.log('[Auth] Profile auto-created:', newProfile);
                setProfile(newProfile);
            }
        } catch (err) {
            console.error('[Auth] Auto-create exception:', err);
            setProfile({ id: userId, email, role: 'valet', name: email.split('@')[0] });
        }
    };

    const signIn = async (email, password) => {
        const { data, error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        return data;
    };

    const signOut = async () => {
        await supabase.auth.signOut();
        setUser(null);
        setProfile(null);
    };

    const value = {
        user,
        profile,
        loading,
        signIn,
        signOut,
        role: profile?.role || 'valet',
        companyId: profile?.valet_company_id,
        companyName: profile?.valet_companies?.company_name || 'VALETBook360',
        companyPhone: profile?.valet_companies?.phone || null,
        locationId: profile?.location_id,
        locationName: profile?.location?.name,
    };

    return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};
