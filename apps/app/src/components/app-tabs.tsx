import { NativeTabs } from 'expo-router/unstable-native-tabs';

import { TABS } from '@/components/tabs';
import { useTheme } from '@/theme';

export default function AppTabs() {
  const { colors } = useTheme();
  return (
    <NativeTabs
      backgroundColor={colors.surface}
      iconColor={{ default: colors.textMuted, selected: colors.accentText }}
      labelStyle={{
        default: { color: colors.textMuted },
        selected: { color: colors.accentText },
      }}
      tintColor={colors.accentText}
    >
      {TABS.map((tab) => (
        <NativeTabs.Trigger key={tab.name} name={tab.name}>
          <NativeTabs.Trigger.Label>{tab.label}</NativeTabs.Trigger.Label>
          <NativeTabs.Trigger.Icon sf={{ default: tab.sf, selected: tab.sfSelected }} md={tab.md} />
        </NativeTabs.Trigger>
      ))}
    </NativeTabs>
  );
}
