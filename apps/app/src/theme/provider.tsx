import { DarkTheme, DefaultTheme, ThemeProvider as NavigationThemeProvider } from 'expo-router';
import { createContext, useContext, useMemo, type PropsWithChildren } from 'react';
import { useColorScheme } from 'react-native';

import { colors, radius, space, typography, type ColorTokens } from '@/theme/tokens';

export type Theme = {
  dark: boolean;
  colors: ColorTokens;
  type: typeof typography;
  space: typeof space;
  radius: typeof radius;
};

const themes: Record<'light' | 'dark', Theme> = {
  light: { dark: false, colors: colors.light, type: typography, space, radius },
  dark: { dark: true, colors: colors.dark, type: typography, space, radius },
};

const ThemeContext = createContext<Theme>(themes.light);

/**
 * The hive palette, type scale and spacing. Light hive outside a provider, so
 * a component rendered on its own -- in a test, or a screen that has not been
 * wrapped yet -- still has tokens instead of crashing.
 */
export function useTheme() {
  return useContext(ThemeContext);
}

export function ThemeProvider({ children }: PropsWithChildren) {
  const theme = useColorScheme() === 'dark' ? themes.dark : themes.light;

  // React Navigation paints what we do not: the native tab bar's chrome, the
  // background behind a screen transition. Hand it the same tokens so the
  // seams do not show.
  const navigationTheme = useMemo(() => {
    const base = theme.dark ? DarkTheme : DefaultTheme;
    return {
      ...base,
      dark: theme.dark,
      colors: {
        ...base.colors,
        primary: theme.colors.accentText,
        background: theme.colors.background,
        card: theme.colors.surface,
        text: theme.colors.text,
        border: theme.colors.border,
        notification: theme.colors.accent,
      },
    };
  }, [theme]);

  return (
    <ThemeContext.Provider value={theme}>
      <NavigationThemeProvider value={navigationTheme}>{children}</NavigationThemeProvider>
    </ThemeContext.Provider>
  );
}
