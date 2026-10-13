import * as Linking from 'expo-linking';
import { router, useLocalSearchParams, useTheme } from 'expo-router';
import { useEffect, useState } from 'react';
import { StyleSheet, Text } from 'react-native';

import { authErrorMessage } from '@/auth/errors';
import { AuthScreen, Button, FormMessage } from '@/components/auth-form';
import { supabase } from '@/lib/supabase';

const RESEND_COOLDOWN_SECONDS = 60;

export default function CheckEmail() {
  const { email } = useLocalSearchParams<{ email?: string }>();
  const { colors } = useTheme();
  const [cooldown, setCooldown] = useState(RESEND_COOLDOWN_SECONDS);
  const [sending, setSending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    if (cooldown <= 0) return;
    const timer = setTimeout(() => setCooldown(cooldown - 1), 1000);
    return () => clearTimeout(timer);
  }, [cooldown]);

  async function resend() {
    if (!email) return;
    setSending(true);
    const { error } = await supabase.auth.resend({
      type: 'signup',
      email,
      options: { emailRedirectTo: Linking.createURL('/') },
    });
    setSending(false);
    setMessage(error ? authErrorMessage(error) : 'Sent. Check your inbox.');
    setCooldown(RESEND_COOLDOWN_SECONDS);
  }

  return (
    <AuthScreen title="Check your email">
      <Text style={[styles.body, { color: colors.text }]}>
        {email
          ? `We sent a link to ${email}. Open it on this device to finish setting up your hive.`
          : 'We sent you a link. Open it on this device to finish setting up your hive.'}
      </Text>
      {message ? <FormMessage>{message}</FormMessage> : null}
      {email ? (
        <Button
          label={cooldown > 0 ? `Send again in ${cooldown}s` : 'Send again'}
          onPress={resend}
          busy={sending}
          disabled={cooldown > 0}
        />
      ) : null}
      <Button variant="link" label="Back to sign in" onPress={() => router.replace('/sign-in')} />
    </AuthScreen>
  );
}

const styles = StyleSheet.create({
  body: { fontSize: 16, lineHeight: 22 },
});
