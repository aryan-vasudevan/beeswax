import type { AuthError } from '@supabase/supabase-js';

// Supabase Auth error codes, in words a person can act on. Anything we do
// not recognise gets a generic message rather than a raw server string.
export function authErrorMessage(error: AuthError): string {
  switch (error.code) {
    case 'invalid_credentials':
      return 'That email and password don’t match.';
    case 'email_not_confirmed':
      return 'Confirm your email first -- check your inbox for the link.';
    case 'user_already_exists':
    case 'email_exists':
      return 'There’s already an account with that email. Try signing in.';
    case 'weak_password':
      return 'Choose a stronger password: at least 8 characters, with letters and numbers.';
    case 'over_email_send_rate_limit':
    case 'over_request_rate_limit':
      return 'Too many tries. Wait a minute and try again.';
    case 'unexpected_failure':
      // The sign-up trigger rejects a username taken in the moment between
      // checking and submitting.
      return 'Something went wrong creating your account. If you picked a username, it may have just been taken.';
    default:
      return 'Something went wrong. Try again.';
  }
}
