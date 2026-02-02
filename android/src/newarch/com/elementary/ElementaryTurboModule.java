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
}
