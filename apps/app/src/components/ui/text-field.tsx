import { useState } from 'react';
import { TextInput, View, type StyleProp, type TextInputProps, type ViewStyle } from 'react-native';

import { FocusRing } from '@/components/ui/focus-ring';
import { Text } from '@/components/ui/text';
import { minTouchTarget, useTheme } from '@/theme';

export type TextFieldProps = Omit<TextInputProps, 'placeholderTextColor' | 'style'> & {
  /** Always visible, never a placeholder standing in for one. */
  label: string;
  /** What to do, before anything has gone wrong. */
  helper?: string;
  /** What went wrong. Replaces `helper` while it is set. */
  error?: string;
  style?: StyleProp<ViewStyle>;
};

export function TextField({ label, helper, error, style, ...input }: TextFieldProps) {
  const { colors, radius, space, type } = useTheme();
  const [focused, setFocused] = useState(false);
  const note = error ?? helper;

  return (
    <View style={style}>
      <Text ink="muted" style={{ marginBottom: space.xs }} variant="label">
        {label}
      </Text>
      <View>
        <TextInput
          accessibilityLabel={label}
          accessibilityHint={note}
          placeholderTextColor={colors.textMuted}
          selectionColor={colors.accent}
          {...input}
          onBlur={(event) => {
            setFocused(false);
            input.onBlur?.(event);
          }}
          onFocus={(event) => {
            setFocused(true);
            input.onFocus?.(event);
          }}
          style={[
            type.body,
            {
              backgroundColor: colors.surface,
              borderColor: error ? colors.danger : colors.borderStrong,
              borderRadius: radius.md,
              borderWidth: 1,
              color: colors.text,
              minHeight: minTouchTarget,
              paddingHorizontal: space.md,
              paddingVertical: space.sm,
              textAlignVertical: input.multiline ? 'top' : 'center',
            },
          ]}
        />
        <FocusRing radius={radius.md} visible={focused} />
      </View>
      {note !== undefined && (
        <Text ink={error ? 'danger' : 'muted'} style={{ marginTop: space.xs }} variant="caption">
          {note}
        </Text>
      )}
    </View>
  );
}
