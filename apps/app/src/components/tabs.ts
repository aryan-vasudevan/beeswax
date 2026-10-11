import type { Href } from 'expo-router';
import type { AndroidSymbol, SFSymbol } from 'expo-symbols';

type Tab = {
  name: string;
  href: Href;
  label: string;
  // SF Symbols (iOS), outline and selected.
  sf: SFSymbol;
  sfSelected: SFSymbol;
  // Material Symbols (Android and web).
  md: AndroidSymbol;
};

// The three top-level destinations, shared by the native and web tab bars.
export const TABS: readonly Tab[] = [
  {
    name: 'index',
    href: '/',
    label: 'Hive',
    sf: 'hexagon',
    sfSelected: 'hexagon.fill',
    md: 'hexagon',
  },
  {
    name: 'create',
    href: '/create',
    label: 'Create',
    sf: 'plus.circle',
    sfSelected: 'plus.circle.fill',
    md: 'add_circle',
  },
  {
    name: 'account',
    href: '/account',
    label: 'Account',
    sf: 'person.crop.circle',
    sfSelected: 'person.crop.circle.fill',
    md: 'account_circle',
  },
];
