
#import "../cpp/vendor/elementary/runtime/elem/Runtime.h"
#import <AVFoundation/AVFoundation.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import <RNElementarySpec/RNElementarySpec.h>
#import <React/RCTEventEmitter.h>

// In new arch, extend RCTEventEmitter and conform to NativeElementarySpec
@interface Elementary : RCTEventEmitter <NativeElementarySpec>

#else

#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface Elementary : RCTEventEmitter <RCTBridgeModule>
#endif

@property(nonatomic, strong) AVAudioEngine *audioEngine;
@property(nonatomic, assign) std::shared_ptr<elem::Runtime<float>> runtime;
@property(nonatomic, strong) NSMutableSet<NSString *> *loadedResources;

@end
