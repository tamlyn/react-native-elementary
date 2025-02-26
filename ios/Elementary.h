
#import "../cpp/vendor/elementary/runtime/elem/Runtime.h"
#import <AVFoundation/AVFoundation.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import "generated/RNElementarySpec/RNElementarySpec.h"

@interface Elementary : NSObject <NativeElementarySpec>

#else

#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface Elementary : RCTEventEmitter <RCTBridgeModule>
#endif

@property(nonatomic, strong) AVAudioEngine *audioEngine;
@property(nonatomic, assign) std::shared_ptr<elem::Runtime<float>> runtime;

@end
