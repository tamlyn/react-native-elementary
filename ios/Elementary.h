
#ifdef RCT_NEW_ARCH_ENABLED
#import "RNElementarySpec.h"

@interface Elementary : NSObject <NativeElementarySpec>
#else
#import <React/RCTBridgeModule.h>

@interface Elementary : NSObject <RCTBridgeModule>
#endif

@end
