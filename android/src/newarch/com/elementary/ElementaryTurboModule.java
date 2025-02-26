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
} 