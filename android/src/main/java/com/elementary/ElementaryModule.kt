package com.elementary

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.Promise

class ElementaryModule(reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {

  override fun getName(): String {
    return NAME
  }

  @ReactMethod
  fun getSampleRate(number: Double, promise: Promise) {
    promise.resolve(nativeGetSampleRate())
  }

    @ReactMethod
  fun applyInstructions(message: String) {
    nativeApplyInstructions(message)
  }

  companion object {
    const val NAME = "Elementary"
  }

  init {
    System.loadLibrary("react-native-elementary");
    nativeStartAudioEngine();
  }

  external fun nativeGetSampleRate(): Int;
  external fun nativeApplyInstructions(message: String);
  external fun nativeStartAudioEngine();
}
