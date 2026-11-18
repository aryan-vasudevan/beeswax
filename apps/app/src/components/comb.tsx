import { Children, type ReactNode } from 'react';
import { View, type StyleProp, type ViewStyle } from 'react-native';

import { CELL_HEIGHT_RATIO, CELL_WIDTH } from '@/components/cell';
import { useTheme } from '@/theme';

export type CombProps = {
  /** Cells, in reading order. */
  children: ReactNode;
  cellWidth?: number;
  /** Cells per row. Every other row is offset by half a cell. */
  columns?: number;
  gap?: number;
  style?: StyleProp<ViewStyle>;
};

/**
 * A cluster of cells, tiled the way wax is. This is the small, static kind of
 * comb -- a snapshot and its children, the cells in an empty state. The
 * pannable hive and the accessible comb list it needs are BWX-19.
 */
export function Comb({ children, cellWidth = CELL_WIDTH, columns = 3, gap, style }: CombProps) {
  const { space } = useTheme();
  const spacing = gap ?? space.xs;
  const height = cellWidth * CELL_HEIGHT_RATIO;

  const cells = Children.toArray(children);
  const rows = Array.from({ length: Math.ceil(cells.length / columns) }, (_, row) =>
    cells.slice(row * columns, row * columns + columns),
  );

  return (
    <View style={[{ alignItems: 'flex-start' }, style]}>
      {rows.map((row, index) => (
        <View
          // A row's key is its position, which is exactly what it is.
          key={index}
          style={{
            flexDirection: 'row',
            gap: spacing,
            // Hexagons interlock: a row slots a quarter of a cell up into the
            // row above it, shifted sideways by half a cell.
            marginLeft: index % 2 === 1 ? (cellWidth + spacing) / 2 : 0,
            marginTop: index === 0 ? 0 : spacing - height / 4,
          }}
        >
          {row}
        </View>
      ))}
    </View>
  );
}
