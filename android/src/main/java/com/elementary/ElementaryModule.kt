package com.elementary

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.util.Log
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.LifecycleEventListener
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
  ReactContextBaseJavaModule(reactContext), LifecycleEventListener {

  private val audioManager = reactContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
  private var audioFocusRequest: AudioFocusRequest? = null
  private var hasAudioFocus = false

  private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
    when (focusChange) {
      AudioManager.AUDIOFOCUS_GAIN -> {
        Log.d(TAG, "Audio focus gained, restarting device")
        hasAudioFocus = true
        nativeStartDevice()
      }
      AudioManager.AUDIOFOCUS_LOSS -> {
        Log.d(TAG, "Audio focus lost permanently, stopping device")
        hasAudioFocus = false
        nativeStopDevice()
      }
      AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
        Log.d(TAG, "Audio focus lost transiently, stopping device")
        hasAudioFocus = false
        nativeStopDevice()
      }
      AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
        // Could lower volume instead, but for an audio engine it's safer to stop
        Log.d(TAG, "Audio focus lost (duck), stopping device")
        hasAudioFocus = false
        nativeStopDevice()
      }
    }
  }

  // Handle headphone disconnect (equivalent to iOS AVAudioEngineConfigurationChangeNotification)
  private val noisyAudioReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
      if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
        Log.d(TAG, "Audio becoming noisy (headphones disconnected), restarting device")
        nativeStopDevice()
        nativeStartDevice()
      }
    }
  }

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

  @ReactMethod
  fun getBundlePath(promise: Promise) {
    val dataDir = reactApplicationContext.applicationInfo.dataDir
    promise.resolve(dataDir)
  }

  @ReactMethod
  fun setProperty(nodeHash: Double, key: String, value: Double) {
    // Build a SET_PROPERTY instruction batch: [[3, nodeHash, key, value]]
    // InstructionType::SET_PROPERTY = 3
    val instruction = "[3,${nodeHash.toInt()},\"$key\",$value]"
    val batch = "[$instruction]"
    nativeApplyInstructions(batch)
  }

  @ReactMethod
  fun getAudioInfo(promise: Promise) {
    val info = Arguments.createMap().apply {
      putInt("channels", nativeGetNumChannels())
      putInt("sampleRate", nativeGetSampleRate())
      putBoolean("engineRunning", nativeIsDeviceRunning())
      putBoolean("runtimeReady", nativeGetSampleRate() > 0)
    }
    promise.resolve(info)
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

  private fun requestAudioFocus() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(
          AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        )
        .setOnAudioFocusChangeListener(audioFocusChangeListener)
        .build()
      audioFocusRequest = focusRequest
      val result = audioManager.requestAudioFocus(focusRequest)
      hasAudioFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    } else {
      @Suppress("DEPRECATION")
      val result = audioManager.requestAudioFocus(
        audioFocusChangeListener,
        AudioManager.STREAM_MUSIC,
        AudioManager.AUDIOFOCUS_GAIN
      )
      hasAudioFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }
    Log.d(TAG, "Audio focus requested, granted: $hasAudioFocus")
  }

  private fun abandonAudioFocus() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
    } else {
      @Suppress("DEPRECATION")
      audioManager.abandonAudioFocus(audioFocusChangeListener)
    }
    hasAudioFocus = false
  }

  // LifecycleEventListener
  override fun onHostResume() {
    if (!hasAudioFocus) {
      Log.d(TAG, "Host resumed without audio focus, re-requesting")
      requestAudioFocus()
    }
    if (hasAudioFocus && !nativeIsDeviceRunning()) {
      Log.d(TAG, "Device not running, restarting")
      nativeStartDevice()
      Log.d(TAG, "Device running after start: ${nativeIsDeviceRunning()}")
    }
  }

  override fun onHostPause() {}

  override fun onHostDestroy() {
    abandonAudioFocus()
    try {
      reactApplicationContext.unregisterReceiver(noisyAudioReceiver)
    } catch (_: IllegalArgumentException) {
      // Receiver was not registered
    }
  }

  companion object {
    const val NAME = "Elementary"
    private const val TAG = "Elementary"
  }

  init {
    System.loadLibrary("react-native-elementary")
    nativeStartAudioEngine()

    // Request audio focus
    requestAudioFocus()

    // Register for headphone disconnect events
    val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
    reactContext.registerReceiver(noisyAudioReceiver, filter)

    // Register lifecycle listener for cleanup
    reactContext.addLifecycleEventListener(this)

    Log.d(TAG, "Audio engine initialized (channels=${nativeGetNumChannels()}, sampleRate=${nativeGetSampleRate()})")
  }

  external fun nativeGetSampleRate(): Int
  external fun nativeGetNumChannels(): Int
  external fun nativeIsDeviceRunning(): Boolean
  external fun nativeApplyInstructions(message: String)
  external fun nativeStartAudioEngine()
  external fun nativeStopDevice()
  external fun nativeStartDevice()
  external fun nativeLoadAudioResource(key: String, filePath: String): AudioResourceInfo?
  external fun nativeUnloadAudioResource(key: String): Boolean
}
