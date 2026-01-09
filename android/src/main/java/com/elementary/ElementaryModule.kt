package com.elementary

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule

class ElementaryModule(reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {

  override fun getName(): String {
    return NAME
  }

  @ReactMethod
  fun getSampleRate(promise: Promise) {
    promise.resolve(nativeGetSampleRate())
  }

  @ReactMethod
  fun applyInstructions(message: String) {
    nativeApplyInstructions(message)
  }

  @ReactMethod
  fun addListener(eventName: String) {
    // No-op, RN handles subscription tracking
  }

  @ReactMethod
  fun removeListeners(count: Double) {
    // No-op
  }

  // Helper to emit events
  private fun sendEvent(eventName: String, params: WritableMap?) {
    reactApplicationContext
      .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(eventName, params)
  }

  fun emitAudioPlaybackFinished() {
    sendEvent("AudioPlaybackFinished", null)
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
