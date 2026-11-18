// Checks the colour tokens against WCAG 2.1 AA, so "contrast meets AA" is a
// property of the repo rather than a line in a design document.
// Run it after touching src/theme/tokens.ts:
//
//   npm run check:contrast
//
// Node runs this file directly and strips the types, which is why
// src/theme/tokens.ts must not import anything at runtime.
import { colors, type ColorTokens } from '../src/theme/tokens.ts';

const channels = (color: string) =>
  (color.replace('#', '').match(/../g) ?? []).map((pair) => parseInt(pair, 16) / 255);

const linearize = (channel: number) =>
  channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;

function luminance(color: string) {
  const [r, g, b] = channels(color).map(linearize);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a: string, b: string) {
  const [lighter, darker] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (lighter + 0.05) / (darker + 0.05);
}

/** `top` laid over `bottom` at `alpha`, flattened to one colour. */
function composite(top: string, alpha: number, bottom: string) {
  const under = channels(bottom);
  return `#${channels(top)
    .map((channel, i) => Math.round(255 * (channel * alpha + under[i] * (1 - alpha))))
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('')}`;
}

// The opacity the scrim reaches behind a cell's title. Keep in step with
// SCRIM_STOPS in src/components/cell.tsx.
const SCRIM_ALPHA_UNDER_TITLE = 0.74;

// AA asks 4.5:1 of text, and 3:1 of controls and of graphics you have to see
// to understand the content.
const pairs: { min: number; what: string; of: (t: ColorTokens) => [string, string] }[] = [
  { min: 7, what: 'body text on the canvas', of: (t) => [t.text, t.background] },
  { min: 7, what: 'body text on a card', of: (t) => [t.text, t.surface] },
  { min: 4.5, what: 'body text on a sunken row', of: (t) => [t.text, t.surfaceSunken] },
  { min: 4.5, what: 'body text on a selected row', of: (t) => [t.text, t.surfaceSelected] },
  { min: 4.5, what: 'secondary text on the canvas', of: (t) => [t.textMuted, t.background] },
  { min: 4.5, what: 'secondary text on a card', of: (t) => [t.textMuted, t.surface] },
  { min: 4.5, what: 'secondary text on a sunken row', of: (t) => [t.textMuted, t.surfaceSunken] },
  { min: 4.5, what: 'label on a primary button', of: (t) => [t.onAccent, t.accent] },
  { min: 4.5, what: 'label on a pressed primary button', of: (t) => [t.onAccent, t.accentPressed] },
  {
    min: 4.5,
    what: 'link or selected icon on the canvas',
    of: (t) => [t.accentText, t.background],
  },
  { min: 4.5, what: 'link or selected icon on a card', of: (t) => [t.accentText, t.surface] },
  { min: 4.5, what: 'label on a destructive button', of: (t) => [t.onDanger, t.danger] },
  {
    min: 4.5,
    what: 'label on a pressed destructive button',
    of: (t) => [t.onDanger, t.dangerPressed],
  },
  { min: 4.5, what: 'error text on the canvas', of: (t) => [t.danger, t.background] },
  { min: 4.5, what: 'error text on a card', of: (t) => [t.danger, t.surface] },
  { min: 4.5, what: 'confirmation text on the canvas', of: (t) => [t.success, t.background] },
  { min: 3, what: 'control outline on the canvas', of: (t) => [t.borderStrong, t.background] },
  { min: 3, what: 'control outline on a card', of: (t) => [t.borderStrong, t.surface] },
  { min: 3, what: 'cell edge on the canvas', of: (t) => [t.borderStrong, t.background] },
  { min: 3, what: 'focus ring on the canvas', of: (t) => [t.focus, t.background] },
  { min: 3, what: 'focus ring on a card', of: (t) => [t.focus, t.surface] },
  { min: 4.5, what: 'title over honey', of: (t) => [t.onAccent, t.honey] },
  { min: 4.5, what: 'title over empty wax', of: (t) => [t.text, t.wax] },
  {
    min: 4.5,
    what: 'title over a cover photo',
    // Worst case: a white photo under the scrim.
    of: (t) => [t.onScrim, composite(t.scrim, SCRIM_ALPHA_UNDER_TITLE, '#FFFFFF')],
  },
];

let failed = 0;

function report(min: number, ratio: number, what: string, detail: string) {
  const ok = ratio >= min;
  if (!ok) failed++;
  console.log(
    `${ok ? '  ok' : 'FAIL'}  ${ratio.toFixed(2).padStart(5)}:1  (needs ${min}:1)  ${what}  ${detail}`,
  );
}

for (const [scheme, tokens] of Object.entries(colors)) {
  console.log(`\n${scheme}`);
  for (const { min, what, of } of pairs) {
    const [foreground, background] = of(tokens);
    report(min, contrast(foreground, background), what, `[${foreground} on ${background}]`);
  }

  // How full a cell is, is information (BWX-83), so the fill level has to be
  // visible without colour vision doing the work. Either honey separates from
  // wax on its own, or the line between them separates from both.
  const { honey, wax, honeyEdge } = tokens;
  const byFill = contrast(honey, wax);
  const byEdge = Math.min(contrast(honeyEdge, honey), contrast(honeyEdge, wax));
  report(
    3,
    Math.max(byFill, byEdge),
    'honey level in a cell',
    `[honey/wax ${byFill.toFixed(2)}:1, edge ${byEdge.toFixed(2)}:1]`,
  );
}

if (failed > 0) {
  console.error(`\n${failed} colour pair(s) below WCAG AA.`);
  process.exit(1);
}
console.log(`\nAll ${(pairs.length + 1) * 2} colour pairs meet WCAG AA.`);
