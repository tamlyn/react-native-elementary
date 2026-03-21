#include <jni.h>
#include "react-native-elementary.h"
#include "audioengine.h"


static std::unique_ptr<elementary::AudioEngine> audioEngine;

// Initialize the AudioEngine instance
extern "C"
JNIEXPORT void JNICALL
Java_com_elementary_ElementaryModule_nativeStartAudioEngine(JNIEnv *env, jclass type) {
    audioEngine = std::make_unique<elementary::AudioEngine>();
}

extern "C"
JNIEXPORT void JNICALL
Java_com_elementary_ElementaryModule_nativeApplyInstructions(JNIEnv *env, jclass type, jstring instructions) {
    if (audioEngine) {
        const char *instrCStr = env->GetStringUTFChars(instructions, nullptr);

        if (!instrCStr) {
            return;
        }

        std::string instrStr(instrCStr);


        env->ReleaseStringUTFChars(instructions, instrCStr);

        auto jsonInstructions = elem::js::parseJSON(instrStr);

        audioEngine->getProxy().applyInstructions(jsonInstructions.getArray());
    }
}

extern "C"
JNIEXPORT jint JNICALL
Java_com_elementary_ElementaryModule_nativeGetSampleRate(JNIEnv *env, jclass type)  {
    return audioEngine.get() ? audioEngine->getSampleRate() : 0;
}

extern "C"
JNIEXPORT jint JNICALL
Java_com_elementary_ElementaryModule_nativeGetNumChannels(JNIEnv *env, jclass type) {
    return audioEngine.get() ? audioEngine->getNumChannels() : 0;
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_elementary_ElementaryModule_nativeIsDeviceRunning(JNIEnv *env, jclass type) {
    return audioEngine.get() ? static_cast<jboolean>(audioEngine->isDeviceRunning()) : JNI_FALSE;
}

extern "C"
JNIEXPORT void JNICALL
Java_com_elementary_ElementaryModule_nativeStopDevice(JNIEnv *env, jclass type) {
    if (audioEngine) {
        audioEngine->stopDevice();
    }
}

extern "C"
JNIEXPORT void JNICALL
Java_com_elementary_ElementaryModule_nativeStartDevice(JNIEnv *env, jclass type) {
    if (audioEngine) {
        audioEngine->startDevice();
    }
}

extern "C"
JNIEXPORT jobject JNICALL
Java_com_elementary_ElementaryModule_nativeLoadAudioResource(JNIEnv *env, jclass type, jstring key, jstring filePath) {
    if (!audioEngine) {
        return nullptr;
    }

    const char *keyCStr = env->GetStringUTFChars(key, nullptr);
    const char *filePathCStr = env->GetStringUTFChars(filePath, nullptr);

    if (!keyCStr || !filePathCStr) {
        if (keyCStr) env->ReleaseStringUTFChars(key, keyCStr);
        if (filePathCStr) env->ReleaseStringUTFChars(filePath, filePathCStr);
        return nullptr;
    }

    std::string keyStr(keyCStr);
    std::string filePathStr(filePathCStr);

    env->ReleaseStringUTFChars(key, keyCStr);
    env->ReleaseStringUTFChars(filePath, filePathCStr);

    // Load the audio resource
    elementary::AudioLoadResult result = audioEngine->loadAudioResource(keyStr, filePathStr);

    // Find the AudioResourceInfo class
    jclass infoClass = env->FindClass("com/elementary/AudioResourceInfo");
    if (!infoClass) {
        return nullptr;
    }

    // Get the constructor
    jmethodID constructor = env->GetMethodID(infoClass, "<init>", "(ZLjava/lang/String;Ljava/lang/String;IJID)V");
    if (!constructor) {
        return nullptr;
    }

    // Create the result object
    jstring jKey = env->NewStringUTF(result.info.key.c_str());
    jstring jError = env->NewStringUTF(result.error.c_str());

    jobject infoObj = env->NewObject(
        infoClass,
        constructor,
        static_cast<jboolean>(result.success),
        jError,
        jKey,
        static_cast<jint>(result.info.channels),
        static_cast<jlong>(result.info.sampleCount),
        static_cast<jint>(result.info.sampleRate),
        static_cast<jdouble>(result.info.durationMs)
    );

    return infoObj;
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_elementary_ElementaryModule_nativeUnloadAudioResource(JNIEnv *env, jclass type, jstring key) {
    if (!audioEngine) {
        return JNI_FALSE;
    }

    const char *keyCStr = env->GetStringUTFChars(key, nullptr);
    if (!keyCStr) {
        return JNI_FALSE;
    }

    std::string keyStr(keyCStr);
    env->ReleaseStringUTFChars(key, keyCStr);

    bool result = audioEngine->unloadAudioResource(keyStr);
    return result ? JNI_TRUE : JNI_FALSE;
}

// Process queued runtime events (el.snapshot, el.meter, el.scope, el.fft).
// Called at ~30Hz by the Kotlin event polling timer.
// Returns a JSON array of events, each with {type, ...fields}.
// Kotlin parses and forwards to JS via RCTDeviceEventEmitter.
extern "C"
JNIEXPORT jstring JNICALL
Java_com_elementary_ElementaryModule_nativeProcessQueuedEvents(JNIEnv *env, jclass type) {
    if (!audioEngine) return env->NewStringUTF("[]");

    auto& runtime = audioEngine->getRuntime();

    std::string json = "[";
    bool first = true;

    runtime.processQueuedEvents([&](std::string const& eventType, elem::js::Value data) {
        if (!first) json += ",";
        first = false;

        json += "{\"type\":\"" + eventType + "\"";

        if (data.isObject()) {
            auto const& obj = data.getObject();
            for (auto const& [key, val] : obj) {
                json += ",\"" + key + "\":";
                if (val.isNumber()) {
                    char buf[64];
                    snprintf(buf, sizeof(buf), "%g", (double)(elem::js::Number) val);
                    json += buf;
                } else if (val.isString()) {
                    json += "\"" + (std::string)(elem::js::String) val + "\"";
                }
            }
        } else if (data.isNumber()) {
            char buf[64];
            snprintf(buf, sizeof(buf), "%g", (double)(elem::js::Number) data);
            json += ",\"data\":" + std::string(buf);
        }

        json += "}";
    });

    json += "]";
    return env->NewStringUTF(json.c_str());
}
