// On the web, Supabase uses localStorage by default. During static rendering
// there is no window, so there is nothing to store and no session to find.
export const sessionStorage = typeof window === 'undefined' ? undefined : window.localStorage;
