import { NativeModules, Platform } from 'react-native';
import { Renderer } from '@elemaudio/core';
import { useEffect, useRef, useState } from 'react';
import NativeElementary from './NativeElementary';

const LINKING_ERROR =
  `The package 'react-native-elementary' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go\n';

// Get the native module
const Elementary = NativeElementary || NativeModules.Elementary;

// Fall back to error if module is not available
const ElementaryModule =
  Elementary ??
  new Proxy(
    {},
    {
      get() {
        throw new Error(LINKING_ERROR);
      },
    }
  );

export function getSampleRate(): Promise<number> {
  return ElementaryModule.getSampleRate();
}

export class NativeRenderer extends Renderer {
  constructor(sampleRate: number) {
    super(sampleRate, (instructions: unknown) => {
      ElementaryModule.applyInstructions(JSON.stringify(instructions));
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
