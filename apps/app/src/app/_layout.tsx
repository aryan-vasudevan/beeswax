import { ThemeProvider } from '@/theme';

import AppTabs from '@/components/app-tabs';

export default function RootLayout() {
  return (
    <ThemeProvider>
      <AppTabs />
    </ThemeProvider>
  );
}
