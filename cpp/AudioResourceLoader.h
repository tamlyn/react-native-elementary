#ifndef AUDIORESOURCELOADER_H
#define AUDIORESOURCELOADER_H

#include <string>
#include <vector>
#include <memory>
#include <cstdint>

namespace elementary {

    /**
     * Metadata about a loaded audio resource
     */
    struct AudioResourceInfo {
        std::string key;
        uint32_t channels;
        uint64_t sampleCount;  // samples per channel
        uint32_t sampleRate;
        double durationMs;
    };

    /**
     * Result of loading an audio resource
     */
    struct AudioLoadResult {
        bool success;
        std::string error;
        AudioResourceInfo info;
        std::vector<float> data;  // Deinterleaved: all ch0 samples, then all ch1 samples, etc.
    };

    /**
     * Audio Resource Loader using miniaudio
     *
     * Loads audio files (WAV, MP3, FLAC, etc.) and converts to deinterleaved float32 format
     * suitable for Elementary Audio's Virtual File System.
     */
    class AudioResourceLoader {
    public:
        /**
         * Load an audio file from disk
         * @param key - Unique identifier for this resource
         * @param filePath - Absolute path to the audio file
         * @return AudioLoadResult containing the audio data and metadata, or error info
         */
        static AudioLoadResult loadFile(const std::string& key, const std::string& filePath);
    };

} // namespace elementary

#endif // AUDIORESOURCELOADER_H
