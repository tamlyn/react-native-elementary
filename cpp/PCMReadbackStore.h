#pragma once
#include "AudioResourceLoader.h"
#include <cmath>
#include <mutex>
#include <stdexcept>
#include <unordered_map>

namespace elementary {
// Retained only for explicitly bounded readback loads, never ordinary VFS loads.
// Independent of the render mutex: boxing a chunk must not block the audio thread.
class PCMReadbackStore {
public:
    void put(const std::string& key, AudioLoadResult&& result) {
        std::lock_guard<std::mutex> lock(mutex);
        resources.insert_or_assign(key, std::move(result));
    }
    bool erase(const std::string& key) {
        std::lock_guard<std::mutex> lock(mutex);
        return resources.erase(key) > 0;
    }
    std::vector<float> read(const std::string& key, double start, double count) {
        if (!std::isfinite(start) || !std::isfinite(count) || start < 0 || count < 1
            || std::floor(start) != start || std::floor(count) != count || count > 16384) {
            throw std::runtime_error("Invalid PCM frame range (maximum 16384 frames)");
        }
        std::lock_guard<std::mutex> lock(mutex);
        auto it = resources.find(key);
        if (it == resources.end()) throw std::runtime_error("No PCM readback resource for key");
        const auto& resource = it->second;
        const auto frames = resource.info.sampleCount;
        if (start > frames || count > frames - start) throw std::runtime_error("PCM range exceeds resource");
        const auto offset = static_cast<size_t>(start);
        const auto length = static_cast<size_t>(count);
        const auto channels = resource.info.channels;
        std::vector<float> data(length * channels);
        for (size_t frame = 0; frame < length; ++frame)
            for (size_t channel = 0; channel < channels; ++channel)
                data[frame * channels + channel] = resource.data[channel * frames + offset + frame];
        return data;
    }
private:
    std::mutex mutex;
    std::unordered_map<std::string, AudioLoadResult> resources;
};
}
