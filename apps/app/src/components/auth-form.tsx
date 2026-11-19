import { useTheme } from 'expo-router';
import type { ReactNode } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  type TextInputProps,
  View,
} from 'react-native';

// Plain building blocks for the auth screens. The real visual language comes
// with the design system (BWX-6); these only need to be clear and accessible.

export function AuthScreen({ title, children }: { title: string; children: ReactNode }) {
  const { colors } = useTheme();
  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      style={[styles.flex, { backgroundColor: colors.background }]}
    >
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <View style={styles.column}>
          <Text accessibilityRole="header" style={[styles.title, { color: colors.text }]}>
            {title}
          </Text>
          {children}
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

type FieldProps = TextInputProps & { label: string; error?: string | null; hint?: string | null };

export function Field({ label, error, hint, ...input }: FieldProps) {
  const { colors } = useTheme();
  return (
    <View style={styles.field}>
      <Text style={[styles.label, { color: colors.text }]}>{label}</Text>
      <TextInput
        accessibilityLabel={label}
        placeholderTextColor={colors.border}
        style={[
          styles.input,
          { borderColor: error ? colors.notification : colors.border, color: colors.text },
        ]}
        {...input}
      />
      {error ? (
        <Text
          accessibilityLiveRegion="polite"
          style={[styles.note, { color: colors.notification }]}
        >
          {error}
        </Text>
      ) : hint ? (
        <Text style={[styles.note, styles.muted, { color: colors.text }]}>{hint}</Text>
      ) : null}
    </View>
  );
}

type ButtonProps = {
  label: string;
  onPress: () => void;
  busy?: boolean;
  disabled?: boolean;
  variant?: 'primary' | 'link';
};

export function Button({ label, onPress, busy, disabled, variant = 'primary' }: ButtonProps) {
  const { colors } = useTheme();
  const inactive = disabled || busy;
  if (variant === 'link') {
    return (
      <Pressable
        accessibilityRole="button"
        onPress={onPress}
        disabled={inactive}
        style={styles.link}
      >
        <Text style={[styles.linkText, { color: colors.primary }]}>{label}</Text>
      </Pressable>
    );
  }
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled: inactive, busy }}
      onPress={onPress}
      disabled={inactive}
      style={({ pressed }) => [
        styles.button,
        { backgroundColor: colors.primary, opacity: inactive ? 0.5 : pressed ? 0.8 : 1 },
      ]}
    >
      {busy ? <ActivityIndicator color="#fff" /> : <Text style={styles.buttonText}>{label}</Text>}
    </Pressable>
  );
}

export function FormMessage({ children }: { children: ReactNode }) {
  const { colors } = useTheme();
  return (
    <Text accessibilityLiveRegion="polite" style={[styles.message, { color: colors.notification }]}>
      {children}
    </Text>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  scroll: { flexGrow: 1, justifyContent: 'center', padding: 24 },
  column: { alignSelf: 'center', gap: 16, maxWidth: 420, width: '100%' },
  title: { fontSize: 28, fontWeight: '700', marginBottom: 8 },
  field: { gap: 6 },
  label: { fontSize: 14, fontWeight: '600' },
  input: {
    borderRadius: 10,
    borderWidth: 1,
    fontSize: 16,
    paddingHorizontal: 14,
    paddingVertical: 12,
  },
  note: { fontSize: 13 },
  muted: { opacity: 0.6 },
  button: { alignItems: 'center', borderRadius: 10, marginTop: 8, paddingVertical: 14 },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  link: { alignItems: 'center', paddingVertical: 8 },
  linkText: { fontSize: 15, fontWeight: '500' },
  message: { fontSize: 14 },
});
