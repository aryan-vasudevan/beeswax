import { useId, useState } from 'react';
import {
  Pressable,
  View,
  type ImageSourcePropType,
  type StyleProp,
  type ViewStyle,
} from 'react-native';
import Svg, {
  ClipPath,
  Defs,
  G,
  Image as SvgImage,
  LinearGradient,
  Polygon,
  Rect,
  Stop,
} from 'react-native-svg';

import { Text } from '@/components/ui/text';
import { useTheme } from '@/theme';

/** A pointy-top hexagon is taller than it is wide by exactly this much. */
export const CELL_HEIGHT_RATIO = 2 / Math.sqrt(3);

/** One cell in a comb, at the size the hive uses on a phone. */
export const CELL_WIDTH = 112;

// The cell in its own coordinates: 100 across, flat sides left and right, a
// point at the top and the bottom. Everything inside is a fraction of these,
// so the `width` prop scales the whole drawing.
const W = 100;
const H = W * CELL_HEIGHT_RATIO;
const VERTICES: readonly (readonly [number, number])[] = [
  [50, 0],
  [100, H / 4],
  [100, (H * 3) / 4],
  [50, H],
  [0, (H * 3) / 4],
  [0, H / 4],
];

/**
 * The hexagon, pulled `inset` units towards its centre. A stroke straddles
 * the line it is drawn on, so an outline has to be inset by half its width or
 * the outer half falls off the canvas and the edge looks thin.
 */
function hexagon(inset = 0) {
  const scale = (W / 2 - inset) / (W / 2);
  return VERTICES.map(([x, y]) => `${50 + (x - 50) * scale},${H / 2 + (y - H / 2) * scale}`).join(
    ' ',
  );
}

const EDGE = 1.5;
const SELECTED_EDGE = 3;
const FOCUS_EDGE = 2.5;

// A title over a photo needs its own background. The scrim fades in over the
// lower half and has reached 0.74 where the words start, which is the number
// scripts/check-contrast.mts holds to AA against a white photo.
const SCRIM_STOPS = [
  { offset: 0.3, opacity: 0 },
  { offset: 0.58, opacity: 0.74 },
  { offset: 1, opacity: 0.9 },
];

// The title sits on the bottom edge of the hexagon's full-width band, so one
// line or two both stay inside the slanted edges.
const TITLE_BOTTOM = 0.25;
const TITLE_INSET = 0.12;

export type CellProps = {
  /** A cell with nothing in it yet has no title. */
  title?: string;
  /** The cover photo. Without one the cell is empty wax. */
  cover?: ImageSourcePropType | string;
  width?: number;
  /** Keep the title up. Otherwise it appears on hover, focus and press. */
  showTitle?: boolean;
  selected?: boolean;
  onPress?: () => void;
  /**
   * What a screen reader says instead of the title alone -- "Japan, day 3,
   * 48 photos from 4 people". A hexagon on a canvas is invisible to
   * assistive technology, so this is the cell for anyone not looking at it.
   */
  accessibilityLabel?: string;
  style?: StyleProp<ViewStyle>;
};

/**
 * One snapshot, as a cell in the hive: a hexagon with a cover photo clipped
 * into it, or empty wax when there is no photo yet.
 *
 * Drawn with SVG, which gets the same shape on iOS, Android and web for the
 * handful of cells a screen shows at a time. Rendering a few hundred of them
 * on one canvas is a different problem, and BWX-8 is the spike that decides
 * it. Honey rising as people contribute, amber with age, warm honey on a
 * resurfaced memory and the rest of the hive's states are BWX-83; the seam
 * for them is the clipped group below.
 */
export function Cell({
  title,
  cover,
  width = CELL_WIDTH,
  showTitle = false,
  selected = false,
  onPress,
  accessibilityLabel,
  style,
}: CellProps) {
  const { colors } = useTheme();
  const [hovered, setHovered] = useState(false);
  const [focused, setFocused] = useState(false);

  // SVG ids live in one namespace per document on web, so each cell needs
  // its own or every cell gets the first one's clip.
  const unique = useId().replace(/[^a-zA-Z0-9]/g, '');
  const clipId = `cell-clip-${unique}`;
  const scrimId = `cell-scrim-${unique}`;

  const height = width * CELL_HEIGHT_RATIO;
  const edge = selected ? SELECTED_EDGE : EDGE;
  const label = accessibilityLabel ?? title ?? 'Empty cell';

  const face = (pressed: boolean) => {
    const titled = !!title && (showTitle || cover === undefined || hovered || focused || pressed);
    return (
      <>
        <Svg height={height} viewBox={`0 0 ${W} ${H}`} width={width}>
          <Defs>
            <ClipPath id={clipId}>
              <Polygon points={hexagon()} />
            </ClipPath>
            {cover !== undefined && (
              <LinearGradient id={scrimId} x1="0" x2="0" y1="0" y2="1">
                {SCRIM_STOPS.map((stop) => (
                  <Stop
                    key={stop.offset}
                    offset={stop.offset}
                    stopColor={colors.scrim}
                    stopOpacity={stop.opacity}
                  />
                ))}
              </LinearGradient>
            )}
          </Defs>
          <G clipPath={`url(#${clipId})`} opacity={pressed ? 0.9 : 1}>
            {/* Wax underneath, so a cover that is missing or still loading
                leaves a cell rather than a hole. */}
            <Polygon fill={colors.wax} points={hexagon()} />
            {cover !== undefined && (
              <SvgImage
                height={H}
                href={cover}
                preserveAspectRatio="xMidYMid slice"
                width={W}
                x={0}
                y={0}
              />
            )}
            {cover !== undefined && titled && (
              <Rect fill={`url(#${scrimId})`} height={H} width={W} x={0} y={0} />
            )}
          </G>
          <Polygon
            fill="none"
            points={hexagon(edge / 2)}
            stroke={selected ? colors.accentText : colors.borderStrong}
            strokeWidth={edge}
          />
          {focused && (
            <Polygon
              fill="none"
              points={hexagon(edge + FOCUS_EDGE)}
              stroke={colors.focus}
              strokeWidth={FOCUS_EDGE}
            />
          )}
        </Svg>
        {titled && (
          <View
            pointerEvents="none"
            style={{
              bottom: height * TITLE_BOTTOM,
              left: width * TITLE_INSET,
              position: 'absolute',
              right: width * TITLE_INSET,
            }}
          >
            <Text
              ink={cover === undefined ? 'default' : 'onScrim'}
              numberOfLines={2}
              style={{ textAlign: 'center' }}
              variant="label"
            >
              {title}
            </Text>
          </View>
        )}
      </>
    );
  };

  if (!onPress) {
    return (
      <View accessible accessibilityLabel={label} style={[{ width }, style]}>
        {face(false)}
      </View>
    );
  }

  return (
    <Pressable
      accessibilityLabel={label}
      accessibilityRole="button"
      accessibilityState={{ selected }}
      onBlur={() => setFocused(false)}
      onFocus={() => setFocused(true)}
      onHoverIn={() => setHovered(true)}
      onHoverOut={() => setHovered(false)}
      onPress={onPress}
      style={[{ width }, style]}
    >
      {({ pressed }) => face(pressed)}
    </Pressable>
  );
}
