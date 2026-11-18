import { View } from 'react-native';

import { Text } from '@/components/ui/text';
import { useTheme } from '@/theme';

// Stand-in for screens whose real content belongs to a later ticket.
export function PlaceholderScreen({ title, note }: { title: string; note: string }) {
  const { colors, space } = useTheme();
  return (
    <View
      style={{
        alignItems: 'center',
        backgroundColor: colors.background,
        flex: 1,
        gap: space.sm,
        justifyContent: 'center',
        padding: space.xl,
      }}
    >
      <Text variant="title">{title}</Text>
      <Text ink="muted" style={{ textAlign: 'center' }} variant="body">
        {note}
      </Text>
    </View>
  );
}
