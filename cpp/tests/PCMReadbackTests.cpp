#include "../AudioResourceLoader.h"
#include "../PCMReadbackStore.h"
#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_DEVICE_IO
#include "../miniaudio.h"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <limits>
#include <string>

static void littleEndian(std::ostream& out, uint32_t value, unsigned bytes) {
    for (unsigned byte = 0; byte < bytes; ++byte)
        out.put(static_cast<char>((value >> (8 * byte)) & 0xff));
}

static void writeWav(const std::string& path, uint16_t channels, uint32_t rate,
                     uint32_t frames, bool tone = false) {
    std::ofstream out(path, std::ios::binary);
    const uint32_t bytes = frames * channels * sizeof(int16_t);
    out.write("RIFF", 4); littleEndian(out, 36 + bytes, 4); out.write("WAVEfmt ", 8);
    littleEndian(out, 16, 4); littleEndian(out, 1, 2); littleEndian(out, channels, 2);
    littleEndian(out, rate, 4); littleEndian(out, rate * channels * 2, 4);
    littleEndian(out, channels * 2, 2); littleEndian(out, 16, 2);
    out.write("data", 4); littleEndian(out, bytes, 4);
    if (tone) {
        for (uint32_t frame = 0; frame < frames; ++frame) {
            for (uint16_t channel = 0; channel < channels; ++channel) {
                const double frequency = channel == 0 ? 440.0 : 880.0;
                const double amplitude = channel == 0 ? 0.4 : 0.2;
                auto sample = static_cast<int16_t>(32767 * amplitude * std::sin(
                    2 * 3.141592653589793 * frequency * frame / rate));
                littleEndian(out, static_cast<uint16_t>(sample), 2);
            }
        }
    } else if (bytes > 0) {
        // Sparse silence fixtures exercise admission using real WAV metadata.
        out.seekp(44 + bytes - 1);
        out.put(0);
    }
    assert(out.good());
}

template <typename Action>
static void rejects(Action&& action) {
    bool rejected = false;
    try { action(); } catch (const std::exception&) { rejected = true; }
    assert(rejected);
}

static void verifyDecode(const std::string& path, uint32_t channels, uint32_t rate,
                         uint64_t minFrames, uint64_t maxFrames) {
    auto loaded = elementary::AudioResourceLoader::loadFile("fixture", path, true);
    assert(loaded.success && loaded.error.empty());
    assert(loaded.info.key == "fixture");
    assert(loaded.info.channels == channels && loaded.info.sampleRate == rate);
    const auto frames = loaded.info.sampleCount;
    assert(frames >= minFrames && frames <= maxFrames);
    assert(std::abs(loaded.info.durationMs - 1000.0 * frames / rate) < 0.001);
    const auto planar = loaded.data;
    elementary::PCMReadbackStore store;
    store.put("fixture", std::move(loaded));
    const auto pcm = store.read("fixture", 0, double(frames));
    assert(pcm.size() == frames * channels);
    for (uint64_t frame = 0; frame < frames; ++frame)
        for (uint32_t channel = 0; channel < channels; ++channel)
            assert(pcm[frame * channels + channel] == planar[channel * frames + frame]);

    // Ignore MP3 delay/padding and inspect the stable middle of each channel.
    const auto begin = rate / 20;
    const auto end = rate / 5;
    for (uint32_t channel = 0; channel < channels; ++channel) {
        unsigned crossings = 0;
        for (uint32_t frame = begin + 1; frame < end; ++frame)
            if (pcm[(frame - 1) * channels + channel] <= 0 && pcm[frame * channels + channel] > 0)
                ++crossings;
        const double frequency = double(crossings) * rate / (end - begin);
        assert(std::abs(frequency - (channel == 0 ? 440.0 : 880.0)) < 15);
    }
    const auto chunk = store.read("fixture", 500, 200);
    for (std::size_t i = 0; i < chunk.size(); ++i) assert(chunk[i] == pcm[500 * channels + i]);
    assert(store.erase("fixture"));
    assert(!store.erase("fixture"));
    rejects([&] { store.read("fixture", 0, 1); });
    std::cout << "PASS decode/channel order/pitch/chunks/unload: " << path << '\n';
}

static void verifyRanges() {
    elementary::PCMReadbackStore store;
    elementary::AudioLoadResult resource{};
    resource.success = true;
    resource.info.channels = 1;
    resource.info.sampleCount = 20000;
    resource.data.resize(20000, 0.25f);
    store.put("range", std::move(resource));
    assert(store.read("range", 0, 16384).size() == 16384);
    assert(store.read("range", 19999, 1)[0] == 0.25f);
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double infinity = std::numeric_limits<double>::infinity();
    for (const auto bounds : {std::pair<double, double>{-1, 1}, {0, -1}, {0, 0},
                              {0.5, 1}, {0, 1.5}, {0, 16385}, {0, nan}, {nan, 1},
                              {0, infinity}, {infinity, 1}, {20000, 1}, {19999, 2}})
        rejects([&] { store.read("range", bounds.first, bounds.second); });
    rejects([&] { store.read("missing", 0, 1); });
    std::cout << "PASS integer/finite/chunk/offset bounds and missing keys\n";
}

int main(int argc, char** argv) {
    assert(argc == 3); // compressed fixture directory, temporary output directory
    const std::string fixtures = argv[1], temporary = argv[2];
    const auto mono = temporary + "/mono.wav";
    const auto stereo = temporary + "/stereo.wav";
    writeWav(mono, 1, 8000, 2000, true);
    writeWav(stereo, 2, 48000, 12000, true);
    verifyDecode(mono, 1, 8000, 2000, 2000);
    verifyDecode(stereo, 2, 48000, 12000, 12000);
    verifyDecode(fixtures + "/stereo-48k.mp3", 2, 48000, 12000, 15000);
    verifyDecode(fixtures + "/stereo-48k.flac", 2, 48000, 12000, 12000);
    verifyRanges();

    const auto limit = temporary + "/limit.wav";
    writeWav(limit, 1, 8000, 8000 * 60);
    assert(elementary::AudioResourceLoader::loadFile("limit", limit, true).success);
    const auto tooLong = temporary + "/too-long.wav";
    writeWav(tooLong, 1, 8000, 8000 * 61);
    const auto rejected = elementary::AudioResourceLoader::loadFile("long", tooLong, true);
    assert(!rejected.success && rejected.data.empty());
    assert(elementary::AudioResourceLoader::loadFile("ordinary-vfs", tooLong).success);
    for (const auto limits : {std::pair<uint16_t, uint32_t>{3, 8000}, {1, 4000}, {1, 384000}}) {
        writeWav(limit, limits.first, limits.second, 1000);
        const auto result = elementary::AudioResourceLoader::loadFile("invalid", limit, true);
        assert(!result.success && result.data.empty());
    }
    // Under 60s, but above 32 MiB decoded float PCM.
    writeWav(limit, 2, 192000, 192000 * 23);
    const auto oversized = elementary::AudioResourceLoader::loadFile("large", limit, true);
    assert(!oversized.success && oversized.data.empty());
    assert(!elementary::AudioResourceLoader::loadFile("missing", temporary + "/missing.wav", true).success);
    const auto malformed = temporary + "/malformed.wav";
    { std::ofstream file(malformed); file << "not an audio file"; }
    assert(!elementary::AudioResourceLoader::loadFile("bad", malformed, true).success);
    std::cout << "PASS admission limits, missing/malformed files and unchanged ordinary VFS loads\n";
}
