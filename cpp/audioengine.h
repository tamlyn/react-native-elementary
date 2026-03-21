#ifndef AUDIOENGINE_H
#define AUDIOENGINE_H

#include "../cpp/vendor/elementary/runtime/elem/Runtime.h"
#include "AudioResourceLoader.h"
#include "miniaudio.h"
#include <atomic>
#include <mutex>
#include <unordered_set>

namespace elementary {
    struct DeviceProxy {
        elem::Runtime<float> runtime;
        std::vector<float> scratchData;
        std::atomic<bool> muted{false};

        // Guards concurrent access to runtime between the audio callback
        // (process) and the JS thread (applyInstructions). The audio callback
        // uses try_lock to avoid blocking — outputs silence on contention.
        std::mutex runtimeMutex;

        DeviceProxy(double sampleRate, size_t blockSize)
            : runtime(sampleRate, blockSize), scratchData(2 * blockSize) {}

        /// Thread-safe wrapper: holds runtimeMutex while applying instructions.
        /// The audio callback uses try_lock, so it outputs silence during this call
        /// rather than accessing the runtime concurrently.
        int applyInstructions(elem::js::Array const& batch) {
            std::lock_guard<std::mutex> lock(runtimeMutex);
            return runtime.applyInstructions(batch);
        }

        void process(float* outputData, size_t numChannels, size_t numFrames) {
            if (muted.load(std::memory_order_relaxed)) {
                std::memset(outputData, 0, numChannels * numFrames * sizeof(float));
                return;
            }

            // Try to acquire the lock without blocking. If applyInstructions
            // is in progress, output silence for this block instead of risking
            // heap corruption from concurrent graph mutation + traversal.
            std::unique_lock<std::mutex> lock(runtimeMutex, std::try_to_lock);
            if (!lock.owns_lock()) {
                std::memset(outputData, 0, numChannels * numFrames * sizeof(float));
                return;
            }

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
            DeviceProxy& getProxy();
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
