import { router } from 'expo-router';
import { useState } from 'react';

import { authErrorMessage } from '@/auth/errors';
import { emailProblem } from '@/auth/validation';
import { AuthScreen, Button, Field, FormMessage } from '@/components/auth-form';
import { supabase } from '@/lib/supabase';

export default function SignIn() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [unconfirmed, setUnconfirmed] = useState(false);

  async function submit() {
    setError(null);
    setUnconfirmed(false);
    const problem = emailProblem(email) ?? (password ? null : 'Enter your password.');
    if (problem) {
      setError(problem);
      return;
    }

    setSubmitting(true);
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    setSubmitting(false);

    // On success the session listener flips the guard and the hive opens.
    if (error) {
      setError(authErrorMessage(error));
      setUnconfirmed(error.code === 'email_not_confirmed');
    }
  }

  return (
    <AuthScreen title="Welcome back">
      <Field
        label="Email"
        value={email}
        onChangeText={setEmail}
        autoCapitalize="none"
        autoComplete="email"
        keyboardType="email-address"
        textContentType="emailAddress"
      />
      <Field
        label="Password"
        value={password}
        onChangeText={setPassword}
        secureTextEntry
        autoComplete="current-password"
        textContentType="password"
        onSubmitEditing={submit}
      />
      {error ? <FormMessage>{error}</FormMessage> : null}
      <Button label="Sign in" onPress={submit} busy={submitting} />
      {unconfirmed ? (
        <Button
          variant="link"
          label="Send the confirmation email again"
          onPress={() => router.push({ pathname: '/check-email', params: { email: email.trim() } })}
        />
      ) : null}
      <Button
        variant="link"
        label="New here? Create an account"
        onPress={() => router.replace('/sign-up')}
      />
    </AuthScreen>
  );
}
