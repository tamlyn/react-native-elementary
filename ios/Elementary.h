
#ifdef RCT_NEW_ARCH_ENABLED
#import "RNElementarySpec.h"

@interface Elementary : RCTEventEmitter <NativeElementarySpec>

#else

#import <React/RCTBridgeModule.h>
#import <AVFoundation/AVFoundation.h>
#import <React/RCTEventEmitter.h>

#import "vendor/elementary/runtime/Runtime.h"

@interface Elementary : RCTEventEmitter <RCTBridgeModule>
#endif

@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, assign) std::shared_ptr<elem::Runtime<float>> runtime;

@end
