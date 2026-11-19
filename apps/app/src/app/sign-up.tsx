import * as Linking from 'expo-linking';
import { router } from 'expo-router';
import { useEffect, useState } from 'react';

import { authErrorMessage } from '@/auth/errors';
import {
  emailProblem,
  normalizeUsername,
  passwordProblem,
  usernameProblem,
} from '@/auth/validation';
import { AuthScreen, Button, Field, FormMessage } from '@/components/auth-form';
import { supabase } from '@/lib/supabase';

type Availability = 'unknown' | 'checking' | 'available' | 'taken';

export default function SignUp() {
  const [displayName, setDisplayName] = useState('');
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  // The last username the server answered for, and its answer.
  const [checked, setChecked] = useState<{ name: string; available: boolean } | null>(null);
  const [showProblems, setShowProblems] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Check the username as they type, once it is valid, after a short pause.
  const candidate = normalizeUsername(username);
  const candidateValid = !usernameProblem(username);
  useEffect(() => {
    if (!candidateValid) return;
    let current = true;
    const timer = setTimeout(async () => {
      const { data, error } = await supabase.rpc('username_available', {
        p_username: candidate,
      });
      if (current && !error) setChecked({ name: candidate, available: Boolean(data) });
    }, 400);
    return () => {
      current = false;
      clearTimeout(timer);
    };
  }, [candidate, candidateValid]);

  const availability: Availability = !candidateValid
    ? 'unknown'
    : checked?.name !== candidate
      ? 'checking'
      : checked.available
        ? 'available'
        : 'taken';

  const problems = {
    displayName: displayName.trim() ? null : 'What should people call you?',
    username:
      usernameProblem(username) ?? (availability === 'taken' ? 'That username is taken.' : null),
    email: emailProblem(email),
    password: passwordProblem(password),
  };

  async function submit() {
    setShowProblems(true);
    setError(null);
    if (Object.values(problems).some(Boolean)) return;

    setSubmitting(true);
    const { data, error } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: {
        // Read by the sign-up trigger (handle_new_user) to create the account
        // and self person.
        data: { username: normalizeUsername(username), display_name: displayName.trim() },
        emailRedirectTo: Linking.createURL('/'),
      },
    });
    setSubmitting(false);

    if (error) {
      setError(authErrorMessage(error));
      return;
    }
    // With email confirmation on there is no session yet. If a project ever
    // turns confirmation off, the session arrives and the guard moves on.
    if (!data.session) {
      router.replace({ pathname: '/check-email', params: { email: email.trim() } });
    }
  }

  const usernameHint =
    availability === 'checking'
      ? 'Checking…'
      : availability === 'available'
        ? 'Available'
        : 'How friends find you. Letters, numbers, dots and underscores.';

  return (
    <AuthScreen title="Start your hive">
      <Field
        label="Your name"
        value={displayName}
        onChangeText={setDisplayName}
        autoComplete="name"
        textContentType="name"
        error={showProblems ? problems.displayName : null}
      />
      <Field
        label="Username"
        value={username}
        onChangeText={setUsername}
        autoCapitalize="none"
        autoCorrect={false}
        autoComplete="username-new"
        textContentType="username"
        error={showProblems || availability === 'taken' ? problems.username : null}
        hint={usernameHint}
      />
      <Field
        label="Email"
        value={email}
        onChangeText={setEmail}
        autoCapitalize="none"
        autoComplete="email"
        keyboardType="email-address"
        textContentType="emailAddress"
        error={showProblems ? problems.email : null}
      />
      <Field
        label="Password"
        value={password}
        onChangeText={setPassword}
        secureTextEntry
        autoComplete="new-password"
        textContentType="newPassword"
        error={showProblems ? problems.password : null}
        hint="At least 8 characters, with letters and numbers."
      />
      {error ? <FormMessage>{error}</FormMessage> : null}
      <Button label="Create account" onPress={submit} busy={submitting} />
      <Button
        variant="link"
        label="I already have an account"
        onPress={() => router.replace('/sign-in')}
      />
    </AuthScreen>
  );
}
