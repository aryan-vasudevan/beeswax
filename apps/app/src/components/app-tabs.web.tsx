import { TabList, TabSlot, TabTrigger, TabTriggerSlotProps, Tabs } from 'expo-router/ui';
import { AndroidSymbol, SymbolView } from 'expo-symbols';
import { Pressable, StyleSheet, useWindowDimensions } from 'react-native';

import { Text } from '@/components/ui/text';
import { TABS } from '@/components/tabs';
import { minTouchTarget, useTheme } from '@/theme';

// Below this width the web app uses a bottom bar like the phone apps; above
// it, a side nav with room for wider content.
const SIDE_NAV_MIN_WIDTH = 768;

export default function AppTabs() {
  const wide = useWindowDimensions().width >= SIDE_NAV_MIN_WIDTH;
  const { colors, space } = useTheme();
  return (
    <Tabs style={wide ? styles.row : styles.column}>
      <TabSlot style={styles.slot} />
      <TabList
        style={[
          wide ? styles.sideNav : styles.bottomBar,
          { backgroundColor: colors.surface, borderColor: colors.border },
        ]}
      >
        {wide && (
          <Text style={{ marginBottom: space.lg, paddingHorizontal: space.md }} variant="title">
            Beeswax
          </Text>
        )}
        {TABS.map((tab) => (
          <TabTrigger key={tab.name} name={tab.name} href={tab.href} asChild>
            <NavButton wide={wide} icon={tab.md} label={tab.label} />
          </TabTrigger>
        ))}
      </TabList>
    </Tabs>
  );
}

type NavButtonProps = TabTriggerSlotProps & { wide: boolean; icon: AndroidSymbol; label: string };

function NavButton({ wide, icon, label, isFocused, ...props }: NavButtonProps) {
  const { colors, radius, space } = useTheme();
  return (
    <Pressable
      {...props}
      accessibilityLabel={label}
      style={({ pressed }) => [
        wide ? styles.sideButton : styles.bottomButton,
        {
          borderRadius: radius.md,
          gap: wide ? space.md : space.xs / 2,
          paddingHorizontal: wide ? space.md : space.lg,
        },
        isFocused && { backgroundColor: colors.surfaceSelected },
        pressed && { backgroundColor: colors.surfacePressed },
      ]}
    >
      <SymbolView
        name={{ web: icon }}
        size={24}
        tintColor={isFocused ? colors.accentText : colors.textMuted}
      />
      <Text ink={isFocused ? 'accent' : 'muted'} variant={wide ? 'body' : 'micro'}>
        {label}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  row: { flex: 1, flexDirection: 'row-reverse' },
  column: { flex: 1 },
  slot: { flex: 1 },
  sideNav: {
    flexDirection: 'column',
    justifyContent: 'flex-start',
    borderRightWidth: StyleSheet.hairlineWidth,
    gap: 4,
    padding: 12,
    width: 220,
  },
  sideButton: {
    alignItems: 'center',
    flexDirection: 'row',
    minHeight: minTouchTarget,
  },
  bottomBar: {
    borderTopWidth: StyleSheet.hairlineWidth,
    justifyContent: 'space-around',
    paddingVertical: 6,
  },
  bottomButton: {
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: minTouchTarget,
  },
});
