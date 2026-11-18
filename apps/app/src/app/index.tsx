import { router } from 'expo-router';
import { View } from 'react-native';

import { Cell } from '@/components/cell';
import { Comb } from '@/components/comb';
import { EmptyState } from '@/components/ui/empty-state';
import { useTheme } from '@/theme';

// Five cells of plain wax: what an account with no snapshots in it looks like.
// Nothing invented, nothing to read -- the comb is decoration, and EmptyState
// keeps it away from screen readers.
const EMPTY_COMB = [0, 1, 2, 3, 4];

export default function Hive() {
  const { colors } = useTheme();
  return (
    <View
      style={{
        alignItems: 'center',
        backgroundColor: colors.background,
        flex: 1,
        justifyContent: 'center',
      }}
    >
      <EmptyState
        action={{ label: 'Create a snapshot', onPress: () => router.navigate('/create') }}
        body="Every moment you keep becomes a cell here, linked to the ones around it. The hive you can pan and zoom comes in BWX-19."
        title="Your hive is empty wax"
      >
        <Comb cellWidth={64} columns={3}>
          {EMPTY_COMB.map((index) => (
            <Cell key={index} width={64} />
          ))}
        </Comb>
      </EmptyState>
    </View>
  );
}
