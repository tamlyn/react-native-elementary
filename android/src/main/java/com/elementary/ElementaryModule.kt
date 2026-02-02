package com.elementary

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule

/**
 * Data class for audio resource information returned from native code
 */
data class AudioResourceInfo(
  val success: Boolean,
  val error: String,
  val key: String,
  val channels: Int,
  val sampleCount: Long,
  val sampleRate: Int,
  val durationMs: Double
)

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

  @ReactMethod
  fun loadAudioResource(key: String, filePath: String, promise: Promise) {
    Thread {
      try {
        val result = nativeLoadAudioResource(key, filePath)
        if (result == null) {
          promise.reject("E_NATIVE_ERROR", "Native audio engine not initialized")
          return@Thread
        }

        if (!result.success) {
          promise.reject("E_LOAD_FAILED", result.error)
          return@Thread
        }

        val info = Arguments.createMap().apply {
          putString("key", result.key)
          putInt("channels", result.channels)
          putDouble("sampleCount", result.sampleCount.toDouble())
          putInt("sampleRate", result.sampleRate)
          putDouble("durationMs", result.durationMs)
        }
        promise.resolve(info)
      } catch (e: Exception) {
        promise.reject("E_LOAD_FAILED", e.message, e)
      }
    }.start()
  }

  @ReactMethod
  fun unloadAudioResource(key: String, promise: Promise) {
    try {
      val result = nativeUnloadAudioResource(key)
      promise.resolve(result)
    } catch (e: Exception) {
      promise.reject("E_UNLOAD_FAILED", e.message, e)
    }
  }

  @ReactMethod
  fun getDocumentsDirectory(promise: Promise) {
    val documentsDir = reactApplicationContext.filesDir.absolutePath
    promise.resolve(documentsDir)
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

  external fun nativeGetSampleRate(): Int
  external fun nativeApplyInstructions(message: String)
  external fun nativeStartAudioEngine()
  external fun nativeLoadAudioResource(key: String, filePath: String): AudioResourceInfo?
  external fun nativeUnloadAudioResource(key: String): Boolean
}
