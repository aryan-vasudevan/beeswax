import type { Session } from '@supabase/supabase-js';
import * as Linking from 'expo-linking';
import { createContext, type ReactNode, useContext, useEffect, useState } from 'react';
import { Platform } from 'react-native';

import { supabase } from '@/lib/supabase';

type SessionState = {
  session: Session | null;
  // True until the stored session has been read; routes wait for it so a
  // signed-in user never flashes the sign-in screen.
  loading: boolean;
};

const SessionContext = createContext<SessionState>({ session: null, loading: true });

export function useSession() {
  return useContext(SessionContext);
}

// The confirmation email links back into the app with ?code=... (PKCE).
// Exchanging it for a session signs the user in.
function useConfirmationLinks() {
  const url = Linking.useURL();
  useEffect(() => {
    if (Platform.OS === 'web' || !url) return;
    const code = Linking.parse(url).queryParams?.code;
    if (typeof code === 'string') {
      supabase.auth.exchangeCodeForSession(code).catch(() => {
        // An old or already-used link. Nothing to do: they can sign in.
      });
    }
  }, [url]);
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<SessionState>({ session: null, loading: true });

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setState({ session: data.session, loading: false });
    });
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      setState({ session, loading: false });
    });
    return () => data.subscription.unsubscribe();
  }, []);

  useConfirmationLinks();

  return <SessionContext.Provider value={state}>{children}</SessionContext.Provider>;
}
