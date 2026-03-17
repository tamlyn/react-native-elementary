#import "Elementary.h"

#include "../cpp/AudioResourceLoader.h"
#include "../cpp/vendor/elementary/runtime/elem/AudioBufferResource.h"

@implementation Elementary

RCT_EXPORT_MODULE();

- (instancetype)init
{
  self = [super init];
  if (self) {
    self.loadedResources = [[NSMutableSet alloc] init];

    self.audioEngine = [[AVAudioEngine alloc] init];

    AVAudioFormat *outputFormat = [self.audioEngine.outputNode outputFormatForBus:0];
    AVAudioMixerNode *mixerNode = self.audioEngine.mainMixerNode;

    int numOutputChannels = outputFormat.channelCount;

    const float **inputBuffer = (const float **)calloc(numOutputChannels, sizeof(float *));
    float **outputBuffer = (float **)malloc(numOutputChannels * sizeof(float *));

    NSLog(@"[Elementary] Init: %d output channels, sampleRate=%.0f", numOutputChannels, outputFormat.sampleRate);

    AVAudioSourceNode *sourceNode = [[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(
            BOOL * _Nonnull isSilence,
            const AudioTimeStamp * _Nonnull timestamp,
            AVAudioFrameCount frameCount,
            AudioBufferList * _Nonnull audioBufferList) {

        // Safety: ensure buffer list matches expected channel count
        UInt32 actualChannels = audioBufferList->mNumberBuffers;

        for (UInt32 channel = 0; channel < actualChannels; channel++) {
            memset(audioBufferList->mBuffers[channel].mData, 0,
                   audioBufferList->mBuffers[channel].mDataByteSize);
        }

        if (self.runtime == nullptr) {
            return noErr;
        }

        // Use the ACTUAL buffer count, not the captured init-time count
        // (audio session reconfiguration can change channel count)
        int processChannels = MIN(numOutputChannels, (int)actualChannels);

        for (int channel = 0; channel < processChannels; channel++) {
          outputBuffer[channel] = (float*)audioBufferList->mBuffers[channel].mData;
        }

        self.runtime->process(
            inputBuffer,
            processChannels,
            outputBuffer,
            processChannels,
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

    int bufferSize = 512;
    self.runtime = std::make_shared<elem::Runtime<float>>(outputFormat.sampleRate, bufferSize);

    // Handle audio session interruptions (phone calls, background, etc.)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAudioInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:[AVAudioSession sharedInstance]];

    // Handle audio engine configuration changes (headphones plugged/unplugged, etc.)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleEngineConfigChange:)
                                                 name:AVAudioEngineConfigurationChangeNotification
                                               object:self.audioEngine];
  }
  return self;
}

- (void)handleAudioInterruption:(NSNotification *)notification {
  NSDictionary *info = notification.userInfo;
  AVAudioSessionInterruptionType type = (AVAudioSessionInterruptionType)[info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];

  if (type == AVAudioSessionInterruptionTypeEnded) {
    // Reactivate audio session and restart engine
    NSError *error;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (error) {
      NSLog(@"[Elementary] Failed to reactivate audio session: %@", error.localizedDescription);
      return;
    }
    if (![self.audioEngine startAndReturnError:&error]) {
      NSLog(@"[Elementary] Failed to restart engine after interruption: %@", error.localizedDescription);
    } else {
      NSLog(@"[Elementary] Engine restarted after interruption");
    }
  } else {
    NSLog(@"[Elementary] Audio interrupted");
  }
}

- (void)handleEngineConfigChange:(NSNotification *)notification {
  NSLog(@"[Elementary] Engine configuration changed, restarting...");
  NSError *error;
  if (![self.audioEngine startAndReturnError:&error]) {
    NSLog(@"[Elementary] Failed to restart engine after config change: %@", error.localizedDescription);
  } else {
    NSLog(@"[Elementary] Engine restarted after config change");
  }
}

+ (BOOL) requiresMainQueueSetup {
  return YES;
}

#pragma mark - React Native Methods

#ifdef RCT_NEW_ARCH_ENABLED
- (void)applyInstructions:(NSString *)message
#else
RCT_EXPORT_METHOD(applyInstructions:(NSString *)message)
#endif
{
  auto parsed = elem::js::parseJSON([message UTF8String]);
  if (parsed.isArray()) {
    self.runtime->applyInstructions(parsed.getArray());
  }
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)setProperty:(double)nodeHash key:(NSString *)key value:(double)value
#else
RCT_EXPORT_METHOD(setProperty:(double)nodeHash key:(NSString *)key value:(double)value)
#endif
{
  if (self.runtime == nullptr) return;

  // Build a SET_PROPERTY instruction batch: [[3, nodeHash, key, value]]
  // InstructionType::SET_PROPERTY = 3
  elem::js::Array instruction;
  instruction.push_back((double)3);
  instruction.push_back(nodeHash);
  instruction.push_back(std::string([key UTF8String]));
  instruction.push_back(value);

  elem::js::Array batch;
  batch.push_back(instruction);

  self.runtime->applyInstructions(batch);
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)getSampleRate:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject
#else
RCT_EXPORT_METHOD(getSampleRate:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
#endif
{
  NSNumber *sampleRate = @([self.audioEngine.outputNode outputFormatForBus:0].sampleRate);
  resolve(sampleRate);
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)loadAudioResource:(NSString *)key
                 filePath:(NSString *)filePath
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject
#else
RCT_EXPORT_METHOD(loadAudioResource:(NSString *)key
                           filePath:(NSString *)filePath
                           resolver:(RCTPromiseResolveBlock)resolve
                           rejecter:(RCTPromiseRejectBlock)reject)
#endif
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    if (self.runtime == nullptr) {
      reject(@"E_RUNTIME_NOT_INITIALIZED", @"Audio runtime not initialized", nil);
      return;
    }

    std::string keyStr = [key UTF8String];
    std::string filePathStr = [filePath UTF8String];

    elementary::AudioLoadResult result = elementary::AudioResourceLoader::loadFile(keyStr, filePathStr);

    if (!result.success) {
      reject(@"E_LOAD_FAILED", [NSString stringWithUTF8String:result.error.c_str()], nil);
      return;
    }

    size_t numChannels = result.info.channels;
    size_t numSamples = result.info.sampleCount;
    std::vector<float*> channelPtrs(numChannels);
    for (size_t ch = 0; ch < numChannels; ++ch) {
      channelPtrs[ch] = result.data.data() + (ch * numSamples);
    }

    auto resource = std::make_unique<elem::AudioBufferResource>(
      channelPtrs.data(),
      numChannels,
      numSamples
    );
    bool added = self.runtime->addSharedResource(keyStr, std::move(resource));

    if (!added) {
      reject(@"E_KEY_EXISTS", [NSString stringWithFormat:@"Resource with key '%@' already exists", key], nil);
      return;
    }

    @synchronized(self.loadedResources) {
      [self.loadedResources addObject:key];
    }

    NSDictionary *info = @{
      @"key": key,
      @"channels": @(result.info.channels),
      @"sampleCount": @(result.info.sampleCount),
      @"sampleRate": @(result.info.sampleRate),
      @"durationMs": @(result.info.durationMs)
    };

    resolve(info);
  });
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)unloadAudioResource:(NSString *)key
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject
#else
RCT_EXPORT_METHOD(unloadAudioResource:(NSString *)key
                             resolver:(RCTPromiseResolveBlock)resolve
                             rejecter:(RCTPromiseRejectBlock)reject)
#endif
{
  if (self.runtime == nullptr) {
    reject(@"E_RUNTIME_NOT_INITIALIZED", @"Audio runtime not initialized", nil);
    return;
  }

  BOOL found = NO;
  @synchronized(self.loadedResources) {
    if ([self.loadedResources containsObject:key]) {
      [self.loadedResources removeObject:key];
      found = YES;
    }
  }

  if (found) {
    self.runtime->pruneSharedResources();
  }

  resolve(@(found));
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)getDocumentsDirectory:(RCTPromiseResolveBlock)resolve
                       reject:(RCTPromiseRejectBlock)reject
#else
RCT_EXPORT_METHOD(getDocumentsDirectory:(RCTPromiseResolveBlock)resolve
                               rejecter:(RCTPromiseRejectBlock)reject)
#endif
{
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  NSString *documentsDirectory = [paths firstObject];
  resolve(documentsDirectory);
}

#pragma mark - RCTEventEmitter

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"AudioPlaybackFinished"];
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)addListener:(NSString *)eventName {}
- (void)removeListeners:(double)count {}
#endif

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeElementarySpecJSI>(params);
}
#endif

@end
