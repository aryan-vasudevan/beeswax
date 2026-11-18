import { View } from 'react-native';

import { useTheme } from '@/theme';

const INSET = 3;
const WIDTH = 2;

/**
 * The keyboard focus ring, drawn outside the control it belongs to so that
 * showing it never moves anything. Needed mostly on web, where tabbing
 * through a form is how plenty of people use the app; harmless on phones.
 * Hexagons draw their own (see cell.tsx) -- a rounded rectangle will not do.
 */
export function FocusRing({ visible, radius }: { visible: boolean; radius: number }) {
  const { colors } = useTheme();
  if (!visible) return null;
  return (
    <View
      pointerEvents="none"
      style={{
        borderColor: colors.focus,
        borderRadius: radius + INSET,
        borderWidth: WIDTH,
        bottom: -INSET,
        left: -INSET,
        position: 'absolute',
        right: -INSET,
        top: -INSET,
      }}
    />
  );
}
