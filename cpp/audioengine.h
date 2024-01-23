#ifndef AUDIOENGINE_H
#define AUDIOENGINE_H

#include "../cpp/vendor/elementary/runtime/elem/Runtime.h"
#include "miniaudio.h"

namespace elementary {
    struct DeviceProxy {
        elem::Runtime<float> runtime;
        std::vector<float> scratchData;

        DeviceProxy(double sampleRate, size_t blockSize)
            : scratchData(2 * blockSize), runtime(sampleRate, blockSize) {}

        void process(float* outputData, size_t numChannels, size_t numFrames) {
            if (scratchData.size() < (numChannels * numFrames))
                scratchData.resize(numChannels * numFrames);

            auto* deinterleaved = scratchData.data();
            std::array<float*, 2> ptrs {deinterleaved, deinterleaved + numFrames};

            runtime.process(
                nullptr,
                0,
                ptrs.data(),
                numChannels,
                numFrames,
                nullptr
            );

            for (size_t i = 0; i < numChannels; ++i) {
                for (size_t j = 0; j < numFrames; ++j) {
                    outputData[i + numChannels * j] = deinterleaved[i * numFrames + j];
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

        private:
            void initializeDevice();
            static void audioCallback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount);

            std::unique_ptr<DeviceProxy> proxy;
            ma_device_config deviceConfig;
            ma_device device;
            bool deviceInitialized;
    };
}

#endif // AUDIOENGINE_H
