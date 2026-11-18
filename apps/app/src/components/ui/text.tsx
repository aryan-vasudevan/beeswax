import { Text as RNText, type TextProps } from 'react-native';

import { useTheme, type TypeVariant } from '@/theme';

/** Which colour the words are, named by what they sit on or mean. */
export type Ink =
  'default' | 'muted' | 'accent' | 'danger' | 'success' | 'onAccent' | 'onDanger' | 'onScrim';

export type AppTextProps = TextProps & { variant?: TypeVariant; ink?: Ink };

/**
 * Every string the user reads goes through here, so the type scale and the
 * palette are the only sizes and colours in the app. Text scales with the OS
 * text size by default; do not turn that off.
 */
export function Text({ variant = 'body', ink = 'default', style, ...rest }: AppTextProps) {
  const { colors, type } = useTheme();
  const inks: Record<Ink, string> = {
    default: colors.text,
    muted: colors.textMuted,
    accent: colors.accentText,
    danger: colors.danger,
    success: colors.success,
    onAccent: colors.onAccent,
    onDanger: colors.onDanger,
    onScrim: colors.onScrim,
  };
  return <RNText {...rest} style={[type[variant], { color: inks[ink] }, style]} />;
}
