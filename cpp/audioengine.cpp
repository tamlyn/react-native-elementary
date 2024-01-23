#include "audioengine.h"
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

namespace elementary {
    AudioEngine::AudioEngine() : deviceConfig(ma_device_config_init(ma_device_type_playback)), deviceInitialized(false) {
        initializeDevice();
    }

    AudioEngine::~AudioEngine() {
        if (deviceInitialized) {
            ma_device_uninit(&device);
        }
    }

    elem::Runtime<float>& AudioEngine::getRuntime() {
        return proxy->runtime;
    }

    int AudioEngine::getSampleRate() {
        return device.sampleRate;
    }

    void AudioEngine::initializeDevice() {
        proxy = std::make_unique<DeviceProxy>(44100.0, 1024);
        
        deviceConfig.playback.pDeviceID = nullptr;
        deviceConfig.playback.format = ma_format_f32;
        deviceConfig.playback.channels = 2;
        deviceConfig.sampleRate = 44100;
        deviceConfig.dataCallback = audioCallback;
        deviceConfig.pUserData = proxy.get();

        ma_result result = ma_device_init(nullptr, &deviceConfig, &device);
        if (result != MA_SUCCESS) {
            std::cerr << "Failed to start the audio device! Exiting..." << std::endl;
            return;
        }

        deviceInitialized = true;
        ma_device_start(&device);
    }

    // Audio callback function
    void AudioEngine::audioCallback(ma_device* pDevice, void* pOutput, const void* /* pInput */, ma_uint32 frameCount) {
        auto* proxy = static_cast<DeviceProxy*>(pDevice->pUserData);
        auto numChannels = static_cast<size_t>(pDevice->playback.channels);
        auto numFrames = static_cast<size_t>(frameCount);

        proxy->process(static_cast<float*>(pOutput), numChannels, numFrames);
    }
}
