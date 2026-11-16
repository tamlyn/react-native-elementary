#pragma once

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <vector>

/// Serves variable-size host audio callbacks from a renderer that must always
/// be called with one fixed block size.
///
/// Elementary's runtime is built for a fixed block size: its buffers hold that
/// many frames, and feedback taps (`el.tapIn` / `el.tapOut`) carry exactly one
/// block of history from the start of their buffers. iOS, however, asks an
/// AVAudioSourceNode for whatever frame count it likes (512 against a
/// 470-frame runtime, more while the screen is locked). Rendering more than the
/// block overruns the buffers; rendering a short remainder (470, 42, 470, …)
/// splices stale tap history into the feedback. So every render is a full
/// block into preallocated scratch, and frames the host didn't ask for yet are
/// carried over to its next callback. The cost is up to one block of latency.
///
/// `configure` allocates and is called off the audio thread (under the same
/// lock as the runtime it pairs with); `render` never allocates.
class FixedBlockRenderer {
public:
    void configure(std::size_t numChannels, std::size_t blockSize)
    {
        channels_ = numChannels;
        blockSize_ = blockSize;
        scratch_.assign(numChannels * blockSize, 0.0f);
        blockPointers_.assign(numChannels, nullptr);
        available_ = 0;
        readPosition_ = 0;
    }

    std::size_t blockSize() const { return blockSize_; }

    /// Fills `numFrames` frames of `output` (one pointer per channel), calling
    /// `renderBlock(float** channels, std::size_t numChannels, std::size_t
    /// blockSize)` with exactly `blockSize()` frames each time it needs more.
    /// Leaves `output` untouched when not configured.
    template <typename RenderBlock>
    void render(float** output, std::size_t numOutputChannels, std::size_t numFrames, RenderBlock&& renderBlock)
    {
        if (blockSize_ == 0 || channels_ == 0)
            return;

        const std::size_t channelsToCopy = std::min(numOutputChannels, channels_);
        std::size_t written = 0;

        while (written < numFrames) {
            if (available_ == 0) {
                for (std::size_t c = 0; c < channels_; ++c)
                    blockPointers_[c] = scratch_.data() + c * blockSize_;

                renderBlock(blockPointers_.data(), channels_, blockSize_);
                available_ = blockSize_;
                readPosition_ = 0;
            }

            const std::size_t count = std::min(numFrames - written, available_);
            for (std::size_t c = 0; c < channelsToCopy; ++c) {
                std::memcpy(output[c] + written,
                            scratch_.data() + c * blockSize_ + readPosition_,
                            count * sizeof(float));
            }

            written += count;
            readPosition_ += count;
            available_ -= count;
        }
    }

private:
    std::size_t channels_ = 0;
    std::size_t blockSize_ = 0;
    std::vector<float> scratch_;
    std::vector<float*> blockPointers_;
    std::size_t available_ = 0;
    std::size_t readPosition_ = 0;
};
