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
