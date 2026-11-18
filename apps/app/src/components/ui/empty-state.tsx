import { View, type StyleProp, type ViewStyle } from 'react-native';
import type { ReactNode } from 'react';

import { Button } from '@/components/ui/button';
import { Text } from '@/components/ui/text';
import { useTheme } from '@/theme';

export type EmptyStateProps = {
  title: string;
  body?: string;
  action?: { label: string; onPress: () => void };
  /**
   * An illustration above the title -- a comb of empty cells, say. Treated as
   * decoration and hidden from screen readers, so never put anything here
   * that the `title` and `body` do not already say.
   */
  children?: ReactNode;
  style?: StyleProp<ViewStyle>;
};

/**
 * Nothing here yet, said calmly. Empty wax is a normal state in the hive, not
 * a failure and not a nudge.
 */
export function EmptyState({ title, body, action, children, style }: EmptyStateProps) {
  const { space } = useTheme();
  return (
    <View
      style={[{ alignItems: 'center', gap: space.md, maxWidth: 420, padding: space.xl }, style]}
    >
      {children && (
        <View
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
          style={{ marginBottom: space.sm }}
        >
          {children}
        </View>
      )}
      <Text style={{ textAlign: 'center' }} variant="title">
        {title}
      </Text>
      {body !== undefined && (
        <Text ink="muted" style={{ textAlign: 'center' }} variant="body">
          {body}
        </Text>
      )}
      {action && <Button label={action.label} onPress={action.onPress} />}
    </View>
  );
}
