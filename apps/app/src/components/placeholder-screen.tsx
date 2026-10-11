import { useTheme } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';

// Stand-in for screens whose real content belongs to a later ticket.
export function PlaceholderScreen({ title, note }: { title: string; note: string }) {
  const { colors } = useTheme();
  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <Text style={[styles.title, { color: colors.text }]}>{title}</Text>
      <Text style={[styles.note, { color: colors.text }]}>{note}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { alignItems: 'center', flex: 1, gap: 8, justifyContent: 'center', padding: 24 },
  title: { fontSize: 24, fontWeight: '600' },
  note: { fontSize: 15, opacity: 0.6, textAlign: 'center' },
});
