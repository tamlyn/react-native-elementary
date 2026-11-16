#pragma once

#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "../cpp/vendor/elementary/runtime/elem/Value.h"

// Inspect the current runtime only while holding its mutex. A contended tick
// leaves events queued; delivery happens after unlocking so listeners may
// re-enter the runtime without deadlocking or blocking the audio callback.
template <typename GetRuntime, typename DeliverEvent>
void pollRuntimeEvents(std::mutex& mutex, GetRuntime&& getRuntime, DeliverEvent&& deliverEvent)
{
    std::vector<std::pair<std::string, elem::js::Value>> events;
    {
        std::unique_lock<std::mutex> lock(mutex, std::try_to_lock);
        if (!lock.owns_lock())
            return;
        auto runtime = getRuntime();
        if (!runtime)
            return;
        runtime->processQueuedEvents([&events](std::string const& type, elem::js::Value data) {
            events.emplace_back(type, std::move(data));
        });
    }
    for (auto const& [type, data] : events)
        deliverEvent(type, data);
}
