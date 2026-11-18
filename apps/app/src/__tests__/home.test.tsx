import { render } from '@testing-library/react-native';
import { DefaultTheme, ThemeProvider } from 'expo-router';

import Hive from '@/app/(app)/index';

// Deliberately small. This exists so the test job has something real to run: it
// proves a screen renders, which is enough to catch a broken preset, transform
// or path alias. Real coverage arrives with the screens in M1.
describe('Hive', () => {
  // `render` is async as of @testing-library/react-native v14 -- without the
  // await you get an unresolved promise and "getByText is not a function".
  it('renders the screen', async () => {
    // The screen reads the navigation theme, which _layout.tsx normally
    // provides. Rendering it bare throws "Couldn't find a theme".
    const { getByText } = await render(
      <ThemeProvider value={DefaultTheme}>
        <Hive />
      </ThemeProvider>,
    );

    expect(getByText('Hive')).toBeTruthy();
  });
});
