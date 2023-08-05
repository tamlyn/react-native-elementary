import { NativeModules, Platform } from 'react-native';
import { Renderer } from '@elemaudio/core';
import { useEffect, useRef, useState } from 'react';

const LINKING_ERROR =
  `The package 'react-native-elementary' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go\n';

const Elementary =
  NativeModules.Elementary ??
  new Proxy(
    {},
    {
      get() {
        throw new Error(LINKING_ERROR);
      },
    }
  );

export function getSampleRate(): Promise<number> {
  // TODO why does this require an argument?
  return Elementary.getSampleRate(1);
}

export class NativeRenderer extends Renderer {
  constructor(sampleRate: number) {
    super(sampleRate, (instructions: unknown) => {
      Elementary.applyInstructions(JSON.stringify(instructions));
    });
  }
}

export function useRenderer(): { core: Renderer | undefined } {
  const [_loading, setLoading] = useState(true);
  const ref = useRef<NativeRenderer>();

  useEffect(() => {
    getSampleRate().then((sampleRate) => {
      ref.current = new NativeRenderer(sampleRate);
      setLoading(false);
    });
  }, []);

  return { core: ref.current };
}
