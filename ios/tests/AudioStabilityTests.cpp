#include "../FixedBlockRenderer.h"
#include "../QueuedEventPoller.h"

#include <cassert>
#include <memory>
#include <thread>

static void testFixedBlocks() {
    FixedBlockRenderer renderer;
    renderer.configure(2, 470);
    std::size_t generated = 0;
    std::size_t consumed = 0;
    auto process = [&](float** output, std::size_t channels, std::size_t frames) {
        assert(channels == 2 && frames == 470);
        for (std::size_t c = 0; c < channels; ++c)
            for (std::size_t f = 0; f < frames; ++f)
                output[c][f] = float(generated + f + c * 100000);
        generated += frames;
    };
    // Short, oversized, background-sized and zero callbacks keep sample order.
    for (std::size_t frames : {512, 42, 0, 4096, 1, 8192, 470}) {
        std::vector<float> left(frames + 2, -1), right(frames + 2, -1);
        float* output[] = {left.data() + 1, right.data() + 1};
        renderer.render(output, 2, frames, process);
        assert(left.front() == -1 && left.back() == -1);
        assert(right.front() == -1 && right.back() == -1);
        for (std::size_t f = 0; f < frames; ++f) {
            assert(left[f + 1] == float(consumed + f));
            assert(right[f + 1] == float(consumed + f + 100000));
        }
        consumed += frames;
    }
    // A missing host channel does not shrink the runtime's DSP channel count.
    float mono[8]{};
    float* output[] = {mono};
    renderer.render(output, 1, 8, process);
    assert(mono[0] == float(consumed));
    renderer.configure(1, 4); // Route reset must discard old carry.
    renderer.render(output, 1, 8, [](float** data, std::size_t channels, std::size_t frames) {
        assert(channels == 1 && frames == 4);
        std::fill_n(data[0], frames, 7.f);
    });
    for (float sample : mono) assert(sample == 7.f);
    renderer.configure(0, 0);
    renderer.render(output, 1, 8, process);
    for (float sample : mono) assert(sample == 7.f);
}

struct FakeRuntime {
    std::mutex& mutex;
    int polls = 0;
    template <typename Callback>
    void processQueuedEvents(Callback&& callback) {
        ++polls;
        callback("meter", elem::js::Value(12.0));
    }
};

static void testQueuedEvents() {
    std::mutex mutex;
    auto runtime = std::make_shared<FakeRuntime>(FakeRuntime{mutex});
    int delivered = 0;
    auto deliver = [&](std::string const& type, elem::js::Value const& value) {
        // A listener may synchronously re-enter runtime code.
        assert(mutex.try_lock());
        mutex.unlock();
        assert(type == "meter" && value.isNumber());
        ++delivered;
    };
    auto getRuntime = [&] { return runtime; };
    pollRuntimeEvents(mutex, getRuntime, deliver);
    assert(runtime->polls == 1 && delivered == 1);
    mutex.lock();
    std::thread contended([&] { pollRuntimeEvents(mutex, getRuntime, deliver); });
    contended.join();
    mutex.unlock();
    assert(runtime->polls == 1 && delivered == 1);
    runtime.reset();
    pollRuntimeEvents(mutex, getRuntime, deliver);
    assert(delivered == 1);
}

int main() {
    testFixedBlocks();
    testQueuedEvents();
}
