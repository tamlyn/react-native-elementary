#ifndef AUDIOENGINE_H
#define AUDIOENGINE_H

#include "../cpp/vendor/elementary/runtime/elem/Runtime.h"
#include "AudioResourceLoader.h"
#include "miniaudio.h"
#include <mutex>
#include <unordered_set>

namespace elementary {
    struct DeviceProxy {
        elem::Runtime<float> runtime;
        std::vector<float> scratchData;

        DeviceProxy(double sampleRate, size_t blockSize)
            : runtime(sampleRate, blockSize), scratchData(2 * blockSize) {}

        void process(float* outputData, size_t numChannels, size_t numFrames) {
            // Clamp to max supported channels (stereo) to prevent out-of-bounds
            // access if the device reports more channels than we can handle
            static constexpr size_t kMaxChannels = 2;
            size_t processChannels = std::min(numChannels, kMaxChannels);

            if (scratchData.size() < (processChannels * numFrames))
                scratchData.resize(processChannels * numFrames);

            auto* deinterleaved = scratchData.data();
            std::array<float*, 2> ptrs {deinterleaved, deinterleaved + numFrames};

            runtime.process(
                nullptr,
                0,
                ptrs.data(),
                processChannels,
                numFrames,
                nullptr
            );

            for (size_t i = 0; i < numChannels; ++i) {
                for (size_t j = 0; j < numFrames; ++j) {
                    if (i < processChannels) {
                        outputData[i + numChannels * j] = deinterleaved[i * numFrames + j];
                    } else {
                        outputData[i + numChannels * j] = 0.0f;
                    }
                }
            }
        }
    };

    class AudioEngine {
        public:
            AudioEngine();
            ~AudioEngine();

            elem::Runtime<float>& getRuntime();
            int getSampleRate();
            int getNumChannels();
            bool isDeviceRunning();
            void stopDevice();
            void startDevice();

            // VFS / Audio Resource methods
            AudioLoadResult loadAudioResource(const std::string& key, const std::string& filePath);
            bool unloadAudioResource(const std::string& key);

        private:
            void initializeDevice();
            static void audioCallback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount);

            std::unique_ptr<DeviceProxy> proxy;
            ma_device_config deviceConfig;
            ma_device device;
            bool deviceInitialized;

            // Track loaded resources for unloading
            std::mutex resourceMutex;
            std::unordered_set<std::string> loadedResources;
    };
}

#endif // AUDIOENGINE_H
