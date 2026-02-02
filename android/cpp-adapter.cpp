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

        audioEngine->getRuntime().applyInstructions(jsonInstructions);
    }
}

extern "C"
JNIEXPORT jint JNICALL
Java_com_elementary_ElementaryModule_nativeGetSampleRate(JNIEnv *env, jclass type)  {
    return audioEngine.get() ? audioEngine->getSampleRate() : 0;
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
