import { useTheme } from 'expo-router';
import { TabList, TabSlot, TabTrigger, TabTriggerSlotProps, Tabs } from 'expo-router/ui';
import { AndroidSymbol, SymbolView } from 'expo-symbols';
import { Pressable, StyleSheet, Text, useWindowDimensions } from 'react-native';

import { TABS } from '@/components/tabs';

// Below this width the web app uses a bottom bar like the phone apps; above
// it, a side nav with room for wider content.
const SIDE_NAV_MIN_WIDTH = 768;

export default function AppTabs() {
  const wide = useWindowDimensions().width >= SIDE_NAV_MIN_WIDTH;
  const { colors } = useTheme();
  return (
    <Tabs style={wide ? styles.row : styles.column}>
      <TabSlot style={styles.slot} />
      <TabList
        style={[
          wide ? styles.sideNav : styles.bottomBar,
          { backgroundColor: colors.card, borderColor: colors.border },
        ]}
      >
        {wide && <Text style={[styles.brand, { color: colors.text }]}>Beeswax</Text>}
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
  const { colors } = useTheme();
  const color = isFocused ? colors.primary : colors.text;
  return (
    <Pressable
      {...props}
      accessibilityLabel={label}
      style={({ pressed }) => [
        wide ? styles.sideButton : styles.bottomButton,
        (isFocused || pressed) && { backgroundColor: colors.border },
      ]}
    >
      <SymbolView name={{ web: icon }} size={24} tintColor={color} />
      <Text style={[wide ? styles.sideLabel : styles.bottomLabel, { color }]}>{label}</Text>
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
  brand: { fontSize: 20, fontWeight: '700', marginBottom: 16, paddingHorizontal: 12 },
  sideButton: {
    alignItems: 'center',
    borderRadius: 8,
    flexDirection: 'row',
    gap: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  sideLabel: { fontSize: 16 },
  bottomBar: {
    borderTopWidth: StyleSheet.hairlineWidth,
    justifyContent: 'space-around',
    paddingVertical: 6,
  },
  bottomButton: {
    alignItems: 'center',
    borderRadius: 8,
    gap: 2,
    paddingHorizontal: 16,
    paddingVertical: 4,
  },
  bottomLabel: { fontSize: 11 },
});
