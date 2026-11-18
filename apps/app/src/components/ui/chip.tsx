import { Image, type ImageSource } from 'expo-image';
import { useState } from 'react';
import { Pressable, View, type StyleProp, type ViewStyle } from 'react-native';
import { SymbolView } from 'expo-symbols';

import { FocusRing } from '@/components/ui/focus-ring';
import { Text } from '@/components/ui/text';
import { minTouchTarget, useTheme } from '@/theme';

const AVATAR = 28;

export type ChipProps = {
  name: string;
  avatar?: ImageSource | string;
  /**
   * A word about who this is, when it matters: "not on Beeswax" for someone
   * who has no account, "you", "added by Sara". People without accounts are
   * first-class, so this reads as a fact and not as a problem.
   */
  note?: string;
  selected?: boolean;
  onPress?: () => void;
  onRemove?: () => void;
  style?: StyleProp<ViewStyle>;
};

/** Initials, so a person without a photo still has a face in the hive. */
function initials(name: string) {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((word) => word[0]?.toUpperCase() ?? '')
    .join('');
}

export function Chip({ name, avatar, note, selected, onPress, onRemove, style }: ChipProps) {
  const { colors, radius, space } = useTheme();
  const [focused, setFocused] = useState(false);

  const body = (
    <>
      <View
        style={{
          alignItems: 'center',
          backgroundColor: colors.surfaceSelected,
          borderRadius: radius.pill,
          height: AVATAR,
          justifyContent: 'center',
          overflow: 'hidden',
          width: AVATAR,
        }}
      >
        {avatar ? (
          <Image alt={name} source={avatar} style={{ height: AVATAR, width: AVATAR }} />
        ) : (
          <Text ink="accent" variant="micro">
            {initials(name)}
          </Text>
        )}
      </View>
      <Text numberOfLines={1} variant="label">
        {name}
      </Text>
      {note !== undefined && (
        <Text ink="muted" numberOfLines={1} variant="caption">
          {note}
        </Text>
      )}
      {onRemove && (
        <Pressable
          accessibilityLabel={`Remove ${name}`}
          accessibilityRole="button"
          hitSlop={space.md}
          onPress={onRemove}
        >
          <SymbolView
            name={{ android: 'close', ios: 'xmark', web: 'close' }}
            size={14}
            tintColor={colors.textMuted}
          />
        </Pressable>
      )}
    </>
  );

  const shell = (pressed: boolean): StyleProp<ViewStyle> => ({
    alignItems: 'center',
    alignSelf: 'flex-start',
    backgroundColor: pressed
      ? colors.surfacePressed
      : selected
        ? colors.surfaceSelected
        : colors.surface,
    borderColor: selected ? colors.accentText : colors.border,
    borderRadius: radius.pill,
    borderWidth: 1,
    flexDirection: 'row',
    gap: space.sm,
    maxWidth: '100%',
    minHeight: minTouchTarget - space.sm,
    paddingHorizontal: space.sm,
    paddingLeft: space.xs,
    paddingVertical: space.xs,
  });

  if (!onPress) {
    return <View style={[shell(false), style]}>{body}</View>;
  }

  return (
    <View style={[{ alignSelf: 'flex-start', maxWidth: '100%' }, style]}>
      <Pressable
        accessibilityLabel={note ? `${name}, ${note}` : name}
        accessibilityRole="button"
        accessibilityState={{ selected }}
        onBlur={() => setFocused(false)}
        onFocus={() => setFocused(true)}
        onPress={onPress}
        style={({ pressed }) => shell(pressed)}
      >
        {body}
      </Pressable>
      <FocusRing radius={radius.pill} visible={focused} />
    </View>
  );
}
