import { useTheme } from 'expo-router';
import { useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { useSession } from '@/auth/session';
import { Button, FormMessage } from '@/components/auth-form';
import { supabase } from '@/lib/supabase';

// Profile, settings and your people come in BWX-12. For now: who you are
// signed in as, and a way out.
export default function Account() {
  const { colors } = useTheme();
  const { session } = useSession();
  const [error, setError] = useState<string | null>(null);

  async function signOut() {
    const { error } = await supabase.auth.signOut();
    if (error) setError('Couldn’t sign out. Try again.');
  }

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <Text style={[styles.title, { color: colors.text }]}>Account</Text>
      <Text style={[styles.note, { color: colors.text }]}>Signed in as {session?.user.email}</Text>
      {error ? <FormMessage>{error}</FormMessage> : null}
      <View style={styles.button}>
        <Button label="Sign out" onPress={signOut} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { alignItems: 'center', flex: 1, gap: 8, justifyContent: 'center', padding: 24 },
  title: { fontSize: 24, fontWeight: '600' },
  note: { fontSize: 15, opacity: 0.7 },
  button: { alignSelf: 'stretch', maxWidth: 320, width: '100%', alignItems: 'stretch' },
});
