package com.elementary;

import androidx.annotation.NonNull;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.Promise;
import com.elementary.NativeElementarySpec;

public class ElementaryTurboModule extends NativeElementarySpec {
    private final ElementaryModule module;

    public ElementaryTurboModule(ReactApplicationContext reactContext) {
        super(reactContext);
        module = new ElementaryModule(reactContext);
    }

    @Override
    public void getSampleRate(Promise promise) {
        module.getSampleRate(promise);
    }

    @Override
    public void applyInstructions(String message) {
        module.applyInstructions(message);
    }

    @Override
    public void activateAudioSession(Promise promise) {
        module.activateAudioSession(promise);
    }

    @Override
    public void deactivateAudioSession(Promise promise) {
        module.deactivateAudioSession(promise);
    }

    @Override
    public void configureAudioSession(String category, String mode, com.facebook.react.bridge.ReadableArray options) {
        module.configureAudioSession(category, mode, options);
    }

    @Override
    public void disableAudioSessionManagement() {
        module.disableAudioSessionManagement();
    }

    @Override
    public void addListener(String eventName) {
        module.addListener(eventName);
    }

    @Override
    public void removeListeners(double count) {
        module.removeListeners(count);
    }

    @Override
    public void loadAudioResource(String key, String filePath, Promise promise) {
        module.loadAudioResource(key, filePath, promise);
    }

    @Override
    public void unloadAudioResource(String key, Promise promise) {
        module.unloadAudioResource(key, promise);
    }

    @Override
    public void getDocumentsDirectory(Promise promise) {
        module.getDocumentsDirectory(promise);
    }

    @Override
    public void getBundlePath(Promise promise) {
        module.getBundlePath(promise);
    }

    @Override
    public void setProperty(double nodeHash, String key, double value) {
        module.setProperty(nodeHash, key, value);
    }

    @Override
    public void startEventPolling(Promise promise) {
        module.startEventPolling(promise);
    }

    @Override
    public void stopEventPolling(Promise promise) {
        module.stopEventPolling(promise);
    }

    @Override
    public void configureEventPolling(double intervalMs, Promise promise) {
        module.configureEventPolling(intervalMs, promise);
    }
}
