import { render } from '@testing-library/react-native';

import Home from '@/app/index';

// Deliberately small. This exists so the test job has something real to run: it
// proves a screen renders, which is enough to catch a broken preset, transform
// or path alias. Real coverage arrives with the screens in M1.
describe('Home', () => {
  // `render` is async as of @testing-library/react-native v14 -- without the
  // await you get an unresolved promise and "getByText is not a function".
  it('renders the app name', async () => {
    const { getByText } = await render(<Home />);

    expect(getByText('Beeswax')).toBeTruthy();
  });
});
