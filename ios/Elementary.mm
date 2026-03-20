#import "Elementary.h"

#include "../cpp/AudioResourceLoader.h"
#include "../cpp/vendor/elementary/runtime/elem/AudioBufferResource.h"

static Elementary *_sharedInstance = nil;

@implementation Elementary

RCT_EXPORT_MODULE();

+ (instancetype)sharedInstance {
  return _sharedInstance;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _sharedInstance = self;
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

        for (UInt8 channel = 0; channel < numOutputChannels; channel++) {
            outputBuffer[channel] = (float*)audioBufferList->mBuffers[channel].mData;
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

    // Start polling for runtime events (el.snapshot, el.meter, el.scope, el.fft).
    // These nodes queue events on the audio thread; processQueuedEvents drains
    // them on the main thread and we forward to JS via RCTEventEmitter.
    [self startEventPolling];
  }
  return self;
}

- (void)startEventPolling {
  if (self.eventPollTimer) return;

  dispatch_source_t timer = dispatch_source_create(
    DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());

  // ~30Hz (33ms interval) — enough for playhead UI, low overhead
  dispatch_source_set_timer(timer,
    dispatch_time(DISPATCH_TIME_NOW, 0),
    33 * NSEC_PER_MSEC,
    5 * NSEC_PER_MSEC);

  __weak Elementary *weakSelf = self;
  dispatch_source_set_event_handler(timer, ^{
    Elementary *strongSelf = weakSelf;
    if (!strongSelf || strongSelf.runtime == nullptr) return;

    strongSelf.runtime->processQueuedEvents([strongSelf](std::string const& type, elem::js::Value data) {
      // Convert C++ event to NSDictionary and send to JS
      NSString *eventType = [NSString stringWithUTF8String:type.c_str()];
      NSMutableDictionary *eventData = [NSMutableDictionary new];
      eventData[@"type"] = eventType;

      if (data.isObject()) {
        auto const& obj = data.getObject();
        for (auto const& [key, val] : obj) {
          NSString *nsKey = [NSString stringWithUTF8String:key.c_str()];
          if (val.isNumber()) {
            eventData[nsKey] = @((double)(elem::js::Number) val);
          } else if (val.isString()) {
            eventData[nsKey] = [NSString stringWithUTF8String:((std::string)(elem::js::String) val).c_str()];
          }
        }
      } else if (data.isNumber()) {
        eventData[@"data"] = @((double)(elem::js::Number) data);
      }

      [strongSelf sendEventWithName:@"elementaryEvent" body:eventData];
    });
  });

  dispatch_resume(timer);
  self.eventPollTimer = timer;
}

- (void)dealloc {
  if (self.eventPollTimer) {
    dispatch_source_cancel(self.eventPollTimer);
    self.eventPollTimer = nil;
  }
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

#pragma mark - Diagnostics

RCT_EXPORT_METHOD(getAudioInfo:(RCTPromiseResolveBlock)resolve
                      rejecter:(RCTPromiseRejectBlock)reject)
{
  AVAudioFormat *format = [self.audioEngine.outputNode outputFormatForBus:0];
  resolve(@{
    @"channels": @(format.channelCount),
    @"sampleRate": @(format.sampleRate),
    @"engineRunning": @(self.audioEngine.isRunning),
    @"runtimeReady": @(self.runtime != nullptr),
  });
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

#ifdef RCT_NEW_ARCH_ENABLED
- (void)getBundlePath:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject
#else
RCT_EXPORT_METHOD(getBundlePath:(RCTPromiseResolveBlock)resolve
                       rejecter:(RCTPromiseRejectBlock)reject)
#endif
{
  NSString *bundlePath = [[NSBundle mainBundle] resourcePath];
  resolve(bundlePath);
}

#pragma mark - RCTEventEmitter

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"AudioPlaybackFinished", @"elementaryEvent"];
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
