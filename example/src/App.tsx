import * as React from 'react';

import { StyleSheet, View, Text } from 'react-native';
import { getSampleRate } from 'react-native-elementary';

export default function App() {
  const [result, setResult] = React.useState<number | undefined>();

  React.useEffect(() => {
    getSampleRate().then(setResult);
  }, []);

  return (
    <View style={styles.container}>
      <Text>Sample rate: {result}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  box: {
    width: 60,
    height: 60,
    marginVertical: 20,
  },
});
