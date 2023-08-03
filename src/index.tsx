import { NativeModules, Platform } from 'react-native';
import { Renderer } from '@elemaudio/core';

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
    super(sampleRate, (instructions: string) => {
      Elementary.applyInstructions(instructions);
    });
  }
}
