#import "Elementary.h"

@implementation Elementary

RCT_EXPORT_MODULE();

- (instancetype)init
{
  self = [super init];
  if (self) {
    self.audioEngine = [[AVAudioEngine alloc] init];

    AVAudioFormat *outputFormat = [self.audioEngine.outputNode outputFormatForBus:0];
    AVAudioMixerNode *mixerNode = self.audioEngine.mainMixerNode;

    int numOutputChannels = outputFormat.channelCount;

    const float **inputBuffer = (const float **)calloc(numOutputChannels, sizeof(float *));
    float **outputBuffer = (float **)malloc(numOutputChannels * sizeof(float *));

    AVAudioSourceNode *sourceNode = [[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(
            BOOL * _Nonnull isSilence,
            const AudioTimeStamp * _Nonnull timestamp,
            AVAudioFrameCount frameCount,
            AudioBufferList * _Nonnull audioBufferList) {

        if (self.runtime == nullptr) {
            // If the runtime is not initialized, return without processing the audio
            return noErr;
        }

        for (UInt8 channel = 0; channel < numOutputChannels; channel++) {
          outputBuffer[channel] = (float*)audioBufferList->mBuffers[channel].mData;;
        }

        self.runtime->process(
            inputBuffer,
            numOutputChannels,
            outputBuffer,
            numOutputChannels,
            frameCount,
            nullptr
        );

        return noErr;
    }];

    [self.audioEngine attachNode:sourceNode];
    [self.audioEngine connect:sourceNode to:mixerNode format:outputFormat];

    NSError *error;
    if (![self.audioEngine startAndReturnError:&error]) {
      NSLog(@"Error starting audio engine: %@", error.localizedDescription);
      return nil;
    }

    // TODO how do I get the frame count from the AVAudioEngine?
    int bufferSize = 512;
    self.runtime = std::make_shared<elem::Runtime<float>>(outputFormat.sampleRate, bufferSize);

    NSLog(@"Started engine and initialised runtime");
  }
  return self;
}

+ (BOOL) requiresMainQueueSetup {
  return YES;
}

RCT_EXPORT_METHOD(applyInstructions:(NSString *)message)
{
  NSLog(@"Applying graph: %@", message);
  self.runtime->applyInstructions(elem::js::parseJSON([message UTF8String]));
}

RCT_EXPORT_METHOD(getSampleRate:
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  NSLog(@"Getting sample rate");
  resolve(@([self.audioEngine.outputNode outputFormatForBus:0].sampleRate));
}

#pragma mark - RCTEventEmitter

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"AudioPlaybackFinished"];
}

// For the new architecture
#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeElementarySpecJSI>(params);
}
#endif
@end
