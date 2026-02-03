#include "../cpp/AudioResourceLoader.h"
#include "../cpp/miniaudio.h"

namespace elementary {

    AudioLoadResult AudioResourceLoader::loadFile(const std::string& key, const std::string& filePath) {
        AudioLoadResult result;
        result.success = false;
        result.info.key = key;

        ma_decoder decoder;
        ma_decoder_config config = ma_decoder_config_init(ma_format_f32, 0, 0);

        ma_result initResult = ma_decoder_init_file(filePath.c_str(), &config, &decoder);
        if (initResult != MA_SUCCESS) {
            result.error = "Failed to open audio file: " + filePath;
            return result;
        }

        ma_uint64 totalFrames;
        ma_result lengthResult = ma_decoder_get_length_in_pcm_frames(&decoder, &totalFrames);
        if (lengthResult != MA_SUCCESS) {
            result.error = "Failed to get audio file length";
            ma_decoder_uninit(&decoder);
            return result;
        }

        uint32_t channels = decoder.outputChannels;
        uint32_t sampleRate = decoder.outputSampleRate;

        std::vector<float> interleavedData(totalFrames * channels);
        ma_uint64 framesRead;
        ma_result readResult = ma_decoder_read_pcm_frames(&decoder, interleavedData.data(), totalFrames, &framesRead);

        ma_decoder_uninit(&decoder);

        if (readResult != MA_SUCCESS && readResult != MA_AT_END) {
            result.error = "Failed to read audio data";
            return result;
        }

        interleavedData.resize(framesRead * channels);

        // Deinterleave into separate channel data
        result.data.resize(framesRead * channels);
        for (uint32_t ch = 0; ch < channels; ++ch) {
            for (ma_uint64 frame = 0; frame < framesRead; ++frame) {
                result.data[ch * framesRead + frame] = interleavedData[frame * channels + ch];
            }
        }

        result.info.channels = channels;
        result.info.sampleCount = static_cast<uint64_t>(framesRead);
        result.info.sampleRate = sampleRate;
        result.info.durationMs = (static_cast<double>(framesRead) / static_cast<double>(sampleRate)) * 1000.0;

        result.success = true;
        return result;
    }

} // namespace elementary
