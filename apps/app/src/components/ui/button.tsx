import { useState } from 'react';
import { ActivityIndicator, Pressable, View, type StyleProp, type ViewStyle } from 'react-native';

import { FocusRing } from '@/components/ui/focus-ring';
import { Text, type Ink } from '@/components/ui/text';
import { minTouchTarget, useTheme } from '@/theme';

export type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger';

export type ButtonProps = {
  label: string;
  onPress: () => void;
  /**
   * `primary` is honey and there is one per screen. `secondary` is the
   * outlined choice next to it, `ghost` the one that barely asks to be
   * pressed, `danger` the one that deletes something.
   */
  variant?: ButtonVariant;
  size?: 'md' | 'sm';
  disabled?: boolean;
  /** Shows a spinner and stops presses, for a save that is in flight. */
  busy?: boolean;
  fullWidth?: boolean;
  accessibilityHint?: string;
  style?: StyleProp<ViewStyle>;
};

export function Button({
  label,
  onPress,
  variant = 'primary',
  size = 'md',
  disabled = false,
  busy = false,
  fullWidth = false,
  accessibilityHint,
  style,
}: ButtonProps) {
  const { colors, radius, space } = useTheme();
  const [hovered, setHovered] = useState(false);
  const [focused, setFocused] = useState(false);
  const inert = disabled || busy;

  type Skin = { fill: string; press: string; edge: string; ink: Ink; spinner: string };
  const skins: Record<ButtonVariant, Skin> = {
    primary: {
      fill: colors.accent,
      press: colors.accentPressed,
      edge: 'transparent',
      ink: 'onAccent',
      spinner: colors.onAccent,
    },
    secondary: {
      fill: 'transparent',
      press: colors.surfacePressed,
      edge: colors.borderStrong,
      ink: 'default',
      spinner: colors.text,
    },
    ghost: {
      fill: 'transparent',
      press: colors.surfacePressed,
      edge: 'transparent',
      ink: 'accent',
      spinner: colors.accentText,
    },
    danger: {
      fill: colors.danger,
      press: colors.dangerPressed,
      edge: 'transparent',
      ink: 'onDanger',
      spinner: colors.onDanger,
    },
  };
  const skin = skins[variant];
  const small = size === 'sm';

  return (
    <View style={[fullWidth ? undefined : { alignSelf: 'flex-start' }, style]}>
      <Pressable
        accessibilityHint={accessibilityHint}
        accessibilityRole="button"
        accessibilityState={{ busy, disabled: inert }}
        disabled={inert}
        // A small button is still 44pt to the finger, just not to the eye.
        hitSlop={small ? space.xs : undefined}
        onBlur={() => setFocused(false)}
        onFocus={() => setFocused(true)}
        onHoverIn={() => setHovered(true)}
        onHoverOut={() => setHovered(false)}
        onPress={onPress}
        style={({ pressed }) => ({
          alignItems: 'center',
          backgroundColor: !inert && (pressed || hovered) ? skin.press : skin.fill,
          borderColor: skin.edge,
          borderRadius: radius.md,
          borderWidth: 1,
          flexDirection: 'row',
          gap: space.sm,
          justifyContent: 'center',
          minHeight: small ? 36 : minTouchTarget,
          opacity: inert ? 0.45 : 1,
          paddingHorizontal: small ? space.md : space.lg,
        })}
      >
        {busy && <ActivityIndicator color={skin.spinner} size="small" />}
        <Text ink={skin.ink} variant="label">
          {label}
        </Text>
      </Pressable>
      <FocusRing radius={radius.md} visible={focused} />
    </View>
  );
}
