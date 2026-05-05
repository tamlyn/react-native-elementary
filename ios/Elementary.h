
#import "../cpp/vendor/elementary/runtime/elem/Runtime.h"
#import <AVFoundation/AVFoundation.h>
#include <mutex>

#ifdef RCT_NEW_ARCH_ENABLED
#import <RNElementarySpec/RNElementarySpec.h>
#import <React/RCTEventEmitter.h>

@interface Elementary : RCTEventEmitter <NativeElementarySpec> {
    /// Guards concurrent access to runtime between the audio render callback
    /// and the JS thread (applyInstructions / setProperty). The audio callback
    /// uses try_lock — outputs silence on contention rather than blocking.
    std::mutex _runtimeMutex;
    int _listenerCount;
    BOOL _hasEventListeners;
}

#else

#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface Elementary : RCTEventEmitter <RCTBridgeModule> {
    std::mutex _runtimeMutex;
    int _listenerCount;
    BOOL _hasEventListeners;
}
#endif

@property(nonatomic, strong) AVAudioEngine *audioEngine;
@property(nonatomic, assign) std::shared_ptr<elem::Runtime<float>> runtime;
@property(nonatomic, strong) NSMutableSet<NSString *> *loadedResources;

/// Timer for processing queued runtime events (el.meter, el.snapshot, el.scope, el.fft).
/// Fires at ~30Hz on the main thread, drains the event queue and forwards to JS.
@property(nonatomic, strong) dispatch_source_t eventPollTimer;

/// Shared instance for native code to access the runtime (e.g. for real-time MIDI triggering)
+ (instancetype)sharedInstance;

@end
