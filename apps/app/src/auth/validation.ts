// Client-side checks that mirror the database and auth config, so the form
// can explain a problem before the server rejects it. The server still
// decides: account.username_format and auth.password_requirements.

export const USERNAME_PATTERN = /^[a-z0-9_.]{3,30}$/;

export function normalizeUsername(raw: string): string {
  return raw.trim().toLowerCase();
}

export function usernameProblem(raw: string): string | null {
  const name = normalizeUsername(raw);
  if (name.length < 3) return 'At least 3 characters.';
  if (name.length > 30) return 'At most 30 characters.';
  if (!USERNAME_PATTERN.test(name)) return 'Letters, numbers, dots and underscores only.';
  return null;
}

export function emailProblem(raw: string): string | null {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(raw.trim()) ? null : 'Enter a valid email.';
}

// Matches supabase/config.toml: minimum_password_length = 8,
// password_requirements = "letters_digits".
export function passwordProblem(password: string): string | null {
  if (password.length < 8) return 'At least 8 characters.';
  if (!/[a-zA-Z]/.test(password) || !/[0-9]/.test(password)) {
    return 'Use both letters and numbers.';
  }
  return null;
}
