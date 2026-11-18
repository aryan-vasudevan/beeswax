import type { TextStyle } from 'react-native';

// The hive palette. Every hex value in the app lives in this file: components
// read the semantic tokens below, never `hive` directly, so a colour can be
// retuned in one place. Nothing here imports from react-native at runtime,
// which is what lets scripts/check-contrast.ts load it in plain Node.
//
// Honey gold is the only colour that acts; cream, wax and charcoal describe.
// The natural accents (clay, sage) are used where meaning demands them and
// nowhere else.
const hive = {
  // Honey gold, light to dark.
  honey100: '#FDF3DC',
  honey200: '#F8DFA4',
  honey300: '#F2C45E',
  honey400: '#E9A72C',
  honey500: '#C8860E',
  honey600: '#8A5B06',
  // Honey in the dark hive: a tint to sit a selected row on.
  honey900: '#2E2213',

  // Warm amber: honey with age in it.
  amber300: '#C98740',
  amber400: '#9C5A18',
  amber500: '#7A4411',

  // Soft cream: the wax the hive is built from, and every light surface.
  cream50: '#FFFDF8',
  cream100: '#FBF6EC',
  cream200: '#F3EADA',
  cream300: '#EADCC4',
  cream400: '#E6D8C1',

  // Muted brown: wax in shadow. Secondary text, borders, cell edges.
  brown200: '#B3A392',
  brown300: '#8C7B63',
  brown500: '#6B5D4F',

  // Charcoal: text in the light hive, every surface in the dark one.
  charcoal600: '#362F27',
  charcoal700: '#2A241D',
  charcoal800: '#1F1A15',
  charcoal900: '#14110E',
  charcoal1000: '#0D0B09',

  // Restrained natural accents.
  clay200: '#EE8470',
  clay300: '#E8705C',
  clay500: '#A32B1C',
  clay600: '#86231A',
  sage300: '#7FB58E',
  sage500: '#3C6B4A',

  white: '#FFFFFF',
} as const;

export type ColorTokens = {
  /** The canvas every screen sits on. */
  background: string;
  /** Cards, sheets, the tab bar: a surface lifted off the canvas. */
  surface: string;
  /** A row or well pressed into the canvas. */
  surfaceSunken: string;
  /** Surface under a finger or a cursor. */
  surfacePressed: string;
  /** A honey-tinted surface for the selected thing. */
  surfaceSelected: string;
  /** Hairline dividers. Decorative: not held to 3:1. */
  border: string;
  /** The outline of a control or a cell. Held to 3:1. */
  borderStrong: string;
  text: string;
  textMuted: string;
  /** Honey as a filled surface: primary buttons. */
  accent: string;
  /** A press darkens in the light hive and brightens in the dark one, which
   * is the only way both keep their contrast with the label. */
  accentPressed: string;
  /** What sits on top of `accent`. */
  onAccent: string;
  /** Honey as ink: links, selected icons, focus. Held to 4.5:1. */
  accentText: string;
  /** The keyboard focus ring. Held to 3:1. */
  focus: string;
  /** An unfilled cell: wax with no memory in it yet. */
  wax: string;
  /** A filled cell. */
  honey: string;
  /**
   * The line where honey meets wax. In the light hive it is what makes the
   * fill level perceivable, since honey against pale wax cannot reach 3:1 and
   * stay honey; in the dark hive honey and wax already contrast and the line
   * is only a meniscus. check-contrast.mts holds both cases.
   */
  honeyEdge: string;
  /** Age. Cells deepen toward amber over the years (BWX-83). */
  amber: string;
  danger: string;
  dangerPressed: string;
  onDanger: string;
  success: string;
  /** Laid under a title over a cover photo, as a gradient. Solid: the
   * component applies the opacity. */
  scrim: string;
  onScrim: string;
};

export const colors: { light: ColorTokens; dark: ColorTokens } = {
  light: {
    background: hive.cream100,
    surface: hive.cream50,
    surfaceSunken: hive.cream200,
    surfacePressed: hive.cream200,
    surfaceSelected: hive.honey100,
    border: hive.cream400,
    borderStrong: hive.brown300,
    text: hive.charcoal800,
    textMuted: hive.brown500,
    accent: hive.honey400,
    accentPressed: hive.honey500,
    onAccent: hive.charcoal800,
    accentText: hive.honey600,
    focus: hive.honey600,
    wax: hive.cream300,
    honey: hive.honey400,
    honeyEdge: hive.amber500,
    amber: hive.amber400,
    danger: hive.clay500,
    dangerPressed: hive.clay600,
    onDanger: hive.white,
    success: hive.sage500,
    scrim: hive.charcoal800,
    onScrim: hive.cream50,
  },
  dark: {
    background: hive.charcoal900,
    surface: hive.charcoal800,
    surfaceSunken: hive.charcoal1000,
    surfacePressed: hive.charcoal700,
    surfaceSelected: hive.honey900,
    border: hive.charcoal600,
    borderStrong: hive.brown300,
    text: hive.cream100,
    textMuted: hive.brown200,
    accent: hive.honey400,
    accentPressed: hive.honey300,
    onAccent: hive.charcoal800,
    accentText: hive.honey300,
    focus: hive.honey300,
    wax: hive.charcoal700,
    honey: hive.honey400,
    honeyEdge: hive.amber300,
    amber: hive.amber300,
    danger: hive.clay300,
    dangerPressed: hive.clay200,
    onDanger: hive.charcoal800,
    success: hive.sage300,
    scrim: hive.charcoal1000,
    onScrim: hive.cream50,
  },
};

// System fonts for now: SF on iOS, Roboto on Android, the system stack on web.
// A typeface is a decision for the designs in BWX-7; the scale below is not,
// and holds either way. Sizes are in points and scale with the OS text size.
export const typography = {
  /** Screen titles. */
  display: { fontSize: 32, lineHeight: 38, fontWeight: '700', letterSpacing: -0.4 },
  /** Section titles, a cell's name on its own screen. */
  title: { fontSize: 24, lineHeight: 30, fontWeight: '700', letterSpacing: -0.2 },
  heading: { fontSize: 19, lineHeight: 25, fontWeight: '600' },
  body: { fontSize: 16, lineHeight: 23, fontWeight: '400' },
  bodyStrong: { fontSize: 16, lineHeight: 23, fontWeight: '600' },
  /** Buttons, field labels, a participant's name. */
  label: { fontSize: 14, lineHeight: 19, fontWeight: '600' },
  /** Helper text, dates, counts. */
  caption: { fontSize: 13, lineHeight: 18, fontWeight: '400' },
  /** Tab labels and badges. Nothing a user must read. */
  micro: { fontSize: 11, lineHeight: 14, fontWeight: '600' },
} as const satisfies Record<string, TextStyle>;

export type TypeVariant = keyof typeof typography;

/** A 4pt rhythm. Padding and gaps come from here, not from loose numbers. */
export const space = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32, xxxl: 48 } as const;

export const radius = { sm: 6, md: 10, lg: 16, pill: 999 } as const;

/** Nothing tappable is smaller than this, padded with hitSlop if need be. */
export const minTouchTarget = 44;
