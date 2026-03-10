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
                    setUser(session.user);
                    await fetchProfile(session.user);
                    setLoading(false);
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
                .select('*, valet_companies(company_name), location:location_id(id, name)')
                .eq('id', userId)
                .single();

            if (error) {
                console.warn('[Auth] Detailed fetch failed (might be missing location_id column). Trying fallback...');
                const { data: fallbackData, error: fallbackError } = await supabase
                    .from('users')
                    .select('*, valet_companies(company_name)')
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
            // Check if any users exist — first user becomes admin
            const { data: existingUsers } = await supabase
                .from('users')
                .select('id')
                .limit(1);

            const isFirstUser = !existingUsers || existingUsers.length === 0;
            const role = isFirstUser ? 'admin' : 'valet';

            console.log('[Auth] Auto-creating profile, role:', role, '(first user:', isFirstUser, ')');

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
                // Fallback: set a minimal profile so routing works
                setProfile({ id: userId, email, role, name: email.split('@')[0] });
            } else {
                console.log('[Auth] Profile auto-created:', newProfile);
                setProfile(newProfile);
            }
        } catch (err) {
            console.error('[Auth] Auto-create exception:', err);
            setProfile({ id: userId, email, role: 'admin', name: email.split('@')[0] });
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
        locationId: profile?.location_id,
        locationName: profile?.location?.name,
    };

    return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};
