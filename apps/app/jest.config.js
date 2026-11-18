// The `jest-expo` preset mocks the native half of the SDK and sets up the
// Metro-flavoured babel transform for us.
//
// jest-expo also ships per-platform presets (`jest-expo/ios` and friends) which
// would let one run cover iOS, Android and web separately. They do not work in
// this monorepo: unlike the universal preset they do not pass a babel preset to
// babel-jest, so they rely on babel discovering a config file -- and babel's
// root is this workspace, while react-native lives in node_modules at the repo
// root, outside it. Its Flow-typed files then fail to parse. The web export job
// in CI is what covers web-specific breakage instead.
//
// Tests live outside src/app/ because every file in there is a route.

/** @type {import('jest').Config} */
module.exports = {
  preset: 'jest-expo',
  rootDir: __dirname,
  testMatch: ['<rootDir>/src/**/*.test.ts?(x)'],
};
