import { createClient } from '@supabase/supabase-js';
import { AppState, Platform } from 'react-native';

import { sessionStorage } from '@/lib/session-storage';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error(
    'Missing EXPO_PUBLIC_SUPABASE_URL or EXPO_PUBLIC_SUPABASE_ANON_KEY. ' +
      'Copy apps/app/.env.example to apps/app/.env and fill it in from `supabase status`.',
  );
}

export const supabase = createClient(url, anonKey, {
  auth: {
    storage: sessionStorage,
    autoRefreshToken: true,
    persistSession: true,
    // PKCE: the confirmation email carries a one-time code, not tokens, so a
    // link intercepted on the way to the app is useless on its own.
    flowType: 'pkce',
    // The web reads the code from the page URL itself; native apps receive
    // it as a deep link, handled in auth/session.tsx.
    detectSessionInUrl: Platform.OS === 'web',
  },
});

// Native apps only refresh the session while in the foreground, so a phone
// left in a drawer does not burn battery keeping a token alive.
if (Platform.OS !== 'web') {
  AppState.addEventListener('change', (state) => {
    if (state === 'active') supabase.auth.startAutoRefresh();
    else supabase.auth.stopAutoRefresh();
  });
}
