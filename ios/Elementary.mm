#import "Elementary.h"
#import <TargetConditionals.h>

#include "../cpp/AudioResourceLoader.h"
#include "../cpp/vendor/elementary/runtime/elem/AudioBufferResource.h"

static Elementary *_sharedInstance = nil;

#if TARGET_OS_SIMULATOR
// 100 ms of stereo 16-bit PCM silence avoids needlessly looping a one-frame
// asset at audio rate while the shared engine starts.
static const unsigned char kSimulatorRoutePrimerWav[17684] = {
  0x52, 0x49, 0x46, 0x46, 0x0c, 0x45, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45,
  0x66, 0x6d, 0x74, 0x20, 0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00,
  0x44, 0xac, 0x00, 0x00, 0x10, 0xb1, 0x02, 0x00, 0x04, 0x00, 0x10, 0x00,
  0x64, 0x61, 0x74, 0x61, 0xe8, 0x44, 0x00, 0x00,
};
#endif

@implementation Elementary

// Main-thread dispatch policy:
//
// AVAudioEngine.outputNode must be accessed on the main thread to avoid
// an RPC timeout in AURemoteIO::Cleanup when called from a background queue.
//
// Dispatch style per context:
//   dispatch_async(main)  — Promise-based RCT_EXPORT_METHOD methods that
//                           resolve/reject asynchronously.
//   dispatch_sync(main)   — setAudioSessionActive needs a synchronous result
//                           for callers that branch on the return value.
//   dispatch_after(main)  — handleEngineConfigChange defers to avoid
//                           re-entrant deadlock during route changes.
//
// Self-capture policy:
//   One-shot dispatch_async blocks may capture self strongly (no retain cycle).
//   Long-lived or deferred blocks (timers, dispatch_after) must use the
//   __weak/strongSelf pattern to avoid extending module lifetime.

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
    self.shouldManageAudioSession = YES;
    self.audioSessionActive = NO;
    self.desiredAudioSessionCategory = AVAudioSessionCategoryPlayback;
    self.desiredAudioSessionMode = AVAudioSessionModeDefault;
    self.desiredAudioSessionOptions = AVAudioSessionCategoryOptionMixWithOthers |
                                      AVAudioSessionCategoryOptionAllowBluetoothA2DP;
    self.audioEngineInitialized = NO;
  }
  return self;
}

/**
 * Dispatch @c block to the main queue after verifying the audio engine
 * is initialized. If initialization fails, @c reject is called with
 * @c E_AUDIO_ENGINE and the block is not executed.
 *
 * All RCT_EXPORT_METHOD entry points that access AVAudioEngine must use
 * this (or the fast-path check in applyInstructions / setProperty) to
 * avoid AURemoteIO::Cleanup RPC timeouts.
 */
- (void)dispatchMainWithEngineInit:(void (^)(void))block
                            reject:(RCTPromiseRejectBlock)reject {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (![self initializeAudioEngineIfNeeded]) {
      reject(@"E_AUDIO_ENGINE", @"Failed to initialize audio engine", nil);
      return;
    }
    block();
  });
}

#if TARGET_OS_SIMULATOR
- (AVAudioPlayer *)startSimulatorAudioRoutePrimer {
  NSData *silence = [NSData dataWithBytes:kSimulatorRoutePrimerWav
                                   length:sizeof(kSimulatorRoutePrimerWav)];
  NSError *error = nil;
  AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithData:silence error:&error];
  player.numberOfLoops = -1;
  player.volume = 0.0f;
  if (!player || ![player play]) {
    NSLog(@"[Elementary] Failed to prime Simulator audio route: %@", error.localizedDescription);
    return nil;
  }
  NSLog(@"[Elementary] Simulator audio route primed");
  return player;
}
#endif

- (BOOL)initializeAudioEngineIfNeeded {
  if (self.audioEngineInitialized) {
    return YES;
  }

  // AVAudioEngine must be accessed on the main thread to avoid
  // an RPC timeout in AURemoteIO::Cleanup when called from a background queue.
  // All cold-engine callers dispatch to main before calling this method.
  NSAssert([NSThread isMainThread],
           @"initializeAudioEngineIfNeeded must be called from the main thread");

  // Configure and activate the audio session before creating AVAudioEngine.
  NSError *sessionError = nil;
  if (![self setAudioSessionActive:YES error:&sessionError]) {
    NSLog(@"[Elementary] Failed to activate audio session: %@", sessionError.localizedDescription);
    return NO;
  }

#if TARGET_OS_SIMULATOR
  // Simulator CoreAudio can abort if its host output starts while the first
  // AURemoteIO is being reconfigured. Hold a silent client until the shared
  // engine is running so that cleanup never races a cold device start.
  AVAudioPlayer *routePrimer = [self startSimulatorAudioRoutePrimer];
  if (!routePrimer) return NO;
#endif

  self.audioEngine = [[AVAudioEngine alloc] init];

  AVAudioFormat *outputFormat = [self.audioEngine.outputNode outputFormatForBus:0];
  AVAudioMixerNode *mixerNode = self.audioEngine.mainMixerNode;

  int numOutputChannels = outputFormat.channelCount;

  const float **inputBuffer = (const float **)calloc(numOutputChannels, sizeof(float *));
  float **outputBuffer = (float **)malloc(numOutputChannels * sizeof(float *));

  NSLog(@"[Elementary] Init: %d output channels, sampleRate=%.0f, IOBufferDuration=%.4fs",
        numOutputChannels, outputFormat.sampleRate, [AVAudioSession sharedInstance].IOBufferDuration);

  AVAudioSourceNode *sourceNode = [[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(
          BOOL * _Nonnull isSilence,
          const AudioTimeStamp * _Nonnull timestamp,
          AVAudioFrameCount frameCount,
          AudioBufferList * _Nonnull audioBufferList) {

      UInt32 suppliedBufferCount = audioBufferList->mNumberBuffers;
      UInt32 actualChannels = MIN(suppliedBufferCount, (UInt32)numOutputChannels);

      for (UInt32 channel = 0; channel < suppliedBufferCount; channel++) {
          memset(audioBufferList->mBuffers[channel].mData, 0,
                 audioBufferList->mBuffers[channel].mDataByteSize);
      }

      // Try to acquire the lock without blocking. If applyInstructions
      // is in progress on the JS thread, output silence for this block
      // rather than risking heap corruption from concurrent access.
      std::unique_lock<std::mutex> lock(self->_runtimeMutex, std::try_to_lock);
      if (!lock.owns_lock() || self.runtime == nullptr || actualChannels == 0) {
          return noErr;
      }

      for (UInt32 channel = 0; channel < actualChannels; channel++) {
          outputBuffer[channel] = (float*)audioBufferList->mBuffers[channel].mData;
      }

      self.runtime->process(
          inputBuffer,
          actualChannels,
          outputBuffer,
          actualChannels,
          frameCount,
          nullptr
      );

      return noErr;
  }];

  [self.audioEngine attachNode:sourceNode];
  [self.audioEngine connect:sourceNode to:mixerNode format:outputFormat];

  int bufferSize = [self computeMaximumRenderFrames];
  NSLog(@"[Elementary] Runtime max block size: %d frames", bufferSize);
  {
    std::lock_guard<std::mutex> lock(_runtimeMutex);
    self.runtime = std::make_shared<elem::Runtime<float>>(outputFormat.sampleRate, bufferSize);
  }

  NSError *error = nil;
  if (![self.audioEngine startAndReturnError:&error]) {
#if TARGET_OS_SIMULATOR
    [routePrimer stop];
#endif
    NSLog(@"Error starting audio engine: %@", error.localizedDescription);
    return NO;
  }
#if TARGET_OS_SIMULATOR
  [routePrimer stop];
#endif

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleAudioInterruption:)
                                               name:AVAudioSessionInterruptionNotification
                                             object:[AVAudioSession sharedInstance]];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleEngineConfigChange:)
                                               name:AVAudioEngineConfigurationChangeNotification
                                             object:self.audioEngine];

  // Event polling is NOT started automatically.
  // Consumers that need el.snapshot / el.meter / el.scope events must
  // explicitly call startEventPolling (or configureEventPolling +
  // startEventPolling) to opt in. This avoids unnecessary JS thread
  // overhead for apps that only use setProperty for real-time updates.

  self.audioEngineInitialized = YES;
  return YES;
}

- (void)startEventPolling {
  if (self.eventPollTimer) return;

  NSUInteger intervalMs = self.eventPollIntervalMs ?: 33; // Default ~30Hz

  dispatch_source_t timer = dispatch_source_create(
    DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());

  dispatch_source_set_timer(timer,
    dispatch_time(DISPATCH_TIME_NOW, 0),
    intervalMs * NSEC_PER_MSEC,
    5 * NSEC_PER_MSEC);

  __weak Elementary *weakSelf = self;
  dispatch_source_set_event_handler(timer, ^{
    Elementary *strongSelf = weakSelf;
    if (!strongSelf) return;

    std::shared_ptr<elem::Runtime<float>> runtime;
    {
      std::lock_guard<std::mutex> lock(strongSelf->_runtimeMutex);
      runtime = strongSelf.runtime;
    }
    if (runtime == nullptr) return;
    runtime->processQueuedEvents([strongSelf](std::string const& type, elem::js::Value data) {
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

      if (strongSelf->_hasEventListeners) {
        [strongSelf sendEventWithName:@"elementaryEvent" body:eventData];
      } // else: silently discard — no JS listeners yet
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
    NSError *activateError = nil;
    if (![self setAudioSessionActive:YES error:&activateError]) {
      NSLog(@"[Elementary] Failed to reactivate audio session: %@", activateError.localizedDescription);
      return;
    }
    NSError *engineError = nil;
    if (![self.audioEngine startAndReturnError:&engineError]) {
      NSLog(@"[Elementary] Failed to restart engine after interruption: %@", engineError.localizedDescription);
    } else {
      NSLog(@"[Elementary] Engine restarted after interruption");
    }
  } else {
    self.audioSessionActive = NO;
    NSLog(@"[Elementary] Audio interrupted");
  }
}

- (void)handleEngineConfigChange:(NSNotification *)notification {
  NSLog(@"[Elementary] Engine configuration changed, stopping engine...");

  // Stop the engine immediately — it's in an inconsistent state after a
  // config change (route/device/format). Attempting to restart synchronously
  // inside this notification causes an RPC deadlock: the audio subsystem is
  // still mid-reconfiguration, so AudioUnitInitialize times out → abort().
  [self.audioEngine stop];

  // Defer restart to let the audio subsystem finish reconfiguring.
  // 200ms is enough for the OS to release locks and settle the new route.
  __weak Elementary *weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(200 * NSEC_PER_MSEC)),
                 dispatch_get_main_queue(), ^{
    Elementary *strongSelf = weakSelf;
    if (!strongSelf) return;

    NSError *error = nil;
    strongSelf.audioSessionActive = NO;
    if (![strongSelf setAudioSessionActive:YES error:&error]) {
      NSLog(@"[Elementary] Failed to reactivate audio session after config change: %@", error.localizedDescription);
      error = nil;
    }
    // Resize the runtime while the engine is stopped so no callback can observe
    // the previous route's capacity after the new route starts rendering.
    AVAudioFormat *newFormat = [strongSelf.audioEngine.outputNode outputFormatForBus:0];
    int newBufferSize = [strongSelf computeMaximumRenderFrames];
    NSLog(@"[Elementary] Recreating runtime: sampleRate=%.0f, maxBlockSize=%d", newFormat.sampleRate, newBufferSize);
    {
      std::lock_guard<std::mutex> lock(strongSelf->_runtimeMutex);
      strongSelf.runtime = std::make_shared<elem::Runtime<float>>(newFormat.sampleRate, newBufferSize);
    }

    if (![strongSelf.audioEngine startAndReturnError:&error]) {
      NSLog(@"[Elementary] Failed to restart engine after config change: %@", error.localizedDescription);
    } else {
      NSLog(@"[Elementary] Engine restarted after config change");
    }
  });
}

+ (BOOL) requiresMainQueueSetup {
  return YES;
}

#pragma mark - Audio Session Configuration

- (BOOL)desiredAudioSessionOptionsAreSet {
  AVAudioSession *session = [AVAudioSession sharedInstance];
  return [session.category isEqualToString:self.desiredAudioSessionCategory] &&
         [session.mode isEqualToString:self.desiredAudioSessionMode] &&
         session.categoryOptions == self.desiredAudioSessionOptions;
}

- (BOOL)configureAudioSessionWithError:(NSError **)error {
  if (!self.shouldManageAudioSession) {
    return YES;
  }

  AVAudioSession *session = [AVAudioSession sharedInstance];
  if (![self desiredAudioSessionOptionsAreSet]) {
    NSError *categoryError = nil;
    if (![session setCategory:self.desiredAudioSessionCategory
                         mode:self.desiredAudioSessionMode
                      options:self.desiredAudioSessionOptions
                        error:&categoryError]) {
      if (error) *error = categoryError;
      return NO;
    }
  }

  // Compute the preferred buffer duration from the actual session sample rate
  // (after category is set) so the requested buffer equals the intended
  // 512 frames regardless of device sample rate.
  double preferredBufferDuration = 512.0 / session.sampleRate;
  NSError *bufferError = nil;
  if (![session setPreferredIOBufferDuration:preferredBufferDuration error:&bufferError]) {
    if (error) *error = bufferError;
    return NO;
  }


  NSLog(@"[Elementary] Configured audio session: category=%@, mode=%@, options=%lu, IOBufferDuration=%.4fs",
        session.category, session.mode, (unsigned long)session.categoryOptions, session.IOBufferDuration);
  return YES;
}

- (BOOL)setAudioSessionActive:(BOOL)active error:(NSError **)error {
  if (!self.shouldManageAudioSession) {
    return YES;
  }

  // Serialize audio session state changes on the main queue to avoid data
  // races between interruption notifications, dispatch_after blocks, and
  // JS-thread exported methods.
  if ([NSThread isMainThread]) {
    return [self setAudioSessionActiveOnMainThread:active error:error];
  } else {
    __block BOOL result = NO;
    __block NSError *blockError = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
      result = [self setAudioSessionActiveOnMainThread:active error:&blockError];
    });
    if (error && blockError) *error = blockError;
    return result;
  }
}

- (BOOL)setAudioSessionActiveOnMainThread:(BOOL)active error:(NSError **)error {
  if (self.audioSessionActive == active) {
    return YES;
  }


  if (active && ![self configureAudioSessionWithError:error]) {
    return NO;
  }

  BOOL success = [[AVAudioSession sharedInstance] setActive:active error:error];
  if (success) {
    self.audioSessionActive = active;
  }
  return success;
}

- (AVAudioSessionCategory)audioSessionCategoryFromString:(NSString *)category {
  if ([category isEqualToString:@"ambient"]) return AVAudioSessionCategoryAmbient;
  if ([category isEqualToString:@"soloAmbient"]) return AVAudioSessionCategorySoloAmbient;
  if ([category isEqualToString:@"record"]) return AVAudioSessionCategoryRecord;
  if ([category isEqualToString:@"playAndRecord"]) return AVAudioSessionCategoryPlayAndRecord;
  if ([category isEqualToString:@"multiRoute"]) return AVAudioSessionCategoryMultiRoute;
  return AVAudioSessionCategoryPlayback;
}

- (AVAudioSessionMode)audioSessionModeFromString:(NSString *)mode {
  if ([mode isEqualToString:@"voiceChat"]) return AVAudioSessionModeVoiceChat;
  if ([mode isEqualToString:@"videoChat"]) return AVAudioSessionModeVideoChat;
  if ([mode isEqualToString:@"gameChat"]) return AVAudioSessionModeGameChat;
  if ([mode isEqualToString:@"measurement"]) return AVAudioSessionModeMeasurement;
  if ([mode isEqualToString:@"moviePlayback"]) return AVAudioSessionModeMoviePlayback;
  if ([mode isEqualToString:@"spokenAudio"]) return AVAudioSessionModeSpokenAudio;
  if ([mode isEqualToString:@"voicePrompt"]) return AVAudioSessionModeVoicePrompt;
  if ([mode isEqualToString:@"videoRecording"]) return AVAudioSessionModeVideoRecording;
  return AVAudioSessionModeDefault;
}

- (AVAudioSessionCategoryOptions)audioSessionOptionsFromArray:(NSArray *)optionsArray {
  AVAudioSessionCategoryOptions options = 0;
  for (NSString *option in optionsArray) {
    if ([option isEqualToString:@"mixWithOthers"]) {
      options |= AVAudioSessionCategoryOptionMixWithOthers;
    } else if ([option isEqualToString:@"duckOthers"]) {
      options |= AVAudioSessionCategoryOptionDuckOthers;
    } else if ([option isEqualToString:@"defaultToSpeaker"]) {
      options |= AVAudioSessionCategoryOptionDefaultToSpeaker;
    } else if ([option isEqualToString:@"allowBluetoothA2DP"]) {
      options |= AVAudioSessionCategoryOptionAllowBluetoothA2DP;
    } else if ([option isEqualToString:@"allowBluetoothHFP"]) {
      // AVAudioSessionCategoryOptionAllowBluetoothHFP is only available from
      // iOS 18 / Xcode 26+. The underlying value is 0x4 on all iOS versions.
      options |= (AVAudioSessionCategoryOptions)0x4;
    } else if ([option isEqualToString:@"allowAirPlay"]) {
      options |= AVAudioSessionCategoryOptionAllowAirPlay;
    } else if ([option isEqualToString:@"interruptSpokenAudioAndMixWithOthers"]) {
      options |= AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers;
    }
  }
  return options;
}

- (int)computeMaximumRenderFrames {
  int maximumFrames = (int)self.audioEngine.outputNode.AUAudioUnit.maximumFramesToRender;
  return maximumFrames > 0 ? maximumFrames : 4096;
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)activateAudioSession:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject
#else
RCT_EXPORT_METHOD(activateAudioSession:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
#endif
{
  NSError *error = nil;
  if (![self setAudioSessionActive:YES error:&error]) {
    reject(@"E_AUDIO_SESSION", @"Failed to activate audio session", error);
    return;
  }

  resolve(@(YES));
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)deactivateAudioSession:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject
#else
RCT_EXPORT_METHOD(deactivateAudioSession:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
#endif
{
  NSError *error = nil;
  if (![self setAudioSessionActive:NO error:&error]) {
    reject(@"E_AUDIO_SESSION", @"Failed to deactivate audio session", error);
    return;
  }

  resolve(@(YES));
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)configureAudioSession:(NSString *)category
                         mode:(NSString *)mode
                      options:(NSArray *)options
#else
RCT_EXPORT_METHOD(configureAudioSession:(NSString *)category
                  mode:(NSString *)mode
                  options:(NSArray *)options)
#endif
{
  self.shouldManageAudioSession = YES;
  self.desiredAudioSessionCategory = [self audioSessionCategoryFromString:category];
  self.desiredAudioSessionMode = [self audioSessionModeFromString:mode];
  self.desiredAudioSessionOptions = [self audioSessionOptionsFromArray:options];

  if (self.audioSessionActive) {
    NSError *error = nil;
    if (![self configureAudioSessionWithError:&error]) {
      NSLog(@"[Elementary] Failed to update audio session options: %@", error.localizedDescription);
    }
  }
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)disableAudioSessionManagement
#else
RCT_EXPORT_METHOD(disableAudioSessionManagement)
#endif
{
  self.shouldManageAudioSession = NO;
}

#pragma mark - Diagnostics

RCT_EXPORT_METHOD(getAudioInfo:(RCTPromiseResolveBlock)resolve
                      rejecter:(RCTPromiseRejectBlock)reject)
{
  [self dispatchMainWithEngineInit:^{
    AVAudioFormat *format = [self.audioEngine.outputNode outputFormatForBus:0];
    BOOL runtimeReady;
    {
      std::lock_guard<std::mutex> lock(_runtimeMutex);
      runtimeReady = self.runtime != nullptr;
    }
    resolve(@{
      @"channels": @(format.channelCount),
      @"sampleRate": @(format.sampleRate),
      @"engineRunning": @(self.audioEngine.isRunning),
      @"runtimeReady": @(runtimeReady),
    });
  } reject:reject];
}

#pragma mark - React Native Methods

#ifdef RCT_NEW_ARCH_ENABLED
- (void)applyInstructions:(NSString *)message
#else
RCT_EXPORT_METHOD(applyInstructions:(NSString *)message)
#endif
{
  // Fast path: engine already initialized — process synchronously.
  if (self.audioEngineInitialized) {
    auto parsed = elem::js::parseJSON([message UTF8String]);
    if (parsed.isArray()) {
      std::lock_guard<std::mutex> lock(_runtimeMutex);
      self.runtime->applyInstructions(parsed.getArray());
    }
    return;
  }

  // Cold path: engine not yet initialized. Dispatch to main thread to
  // avoid AURemoteIO::Cleanup RPC timeout when accessing AVAudioEngine.
  dispatch_async(dispatch_get_main_queue(), ^{
    if (![self initializeAudioEngineIfNeeded]) return;

    auto parsed = elem::js::parseJSON([message UTF8String]);
    if (parsed.isArray()) {
      std::lock_guard<std::mutex> lock(self->_runtimeMutex);
      self.runtime->applyInstructions(parsed.getArray());
    }
  });
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)setProperty:(double)nodeHash key:(NSString *)key value:(double)value
#else
RCT_EXPORT_METHOD(setProperty:(double)nodeHash key:(NSString *)key value:(double)value)
#endif
{
  // Fast path: engine already initialized — update synchronously.
  if (self.audioEngineInitialized) {
    elem::js::Array instruction;
    instruction.push_back((double)3);
    instruction.push_back(nodeHash);
    instruction.push_back(std::string([key UTF8String]));
    instruction.push_back(value);

    elem::js::Array batch;
    batch.push_back(instruction);

    {
      std::lock_guard<std::mutex> lock(_runtimeMutex);
      if (self.runtime != nullptr) self.runtime->applyInstructions(batch);
    }
    return;
  }

  // Cold path: engine not yet initialized. Dispatch to main thread to
  // avoid AURemoteIO::Cleanup RPC timeout when accessing AVAudioEngine.
  dispatch_async(dispatch_get_main_queue(), ^{
    if (![self initializeAudioEngineIfNeeded]) return;

    // Native integrations apply renderer instruction batches via Runtime::applyInstructions:
    // https://www.elementary.audio/docs/guides/Native_Integrations#applyinstructions
    // The SET_PROPERTY opcode (3) comes from Elementary's Runtime.h.
    elem::js::Array instruction;
    instruction.push_back((double)3);
    instruction.push_back(nodeHash);
    instruction.push_back(std::string([key UTF8String]));
    instruction.push_back(value);

    elem::js::Array batch;
    batch.push_back(instruction);

    {
      std::lock_guard<std::mutex> lock(self->_runtimeMutex);
      if (self.runtime != nullptr) self.runtime->applyInstructions(batch);
    }
  });
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)getSampleRate:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject
#else
RCT_EXPORT_METHOD(getSampleRate:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
#endif
{
  [self dispatchMainWithEngineInit:^{
    NSNumber *sampleRate = @([self.audioEngine.outputNode outputFormatForBus:0].sampleRate);
    resolve(sampleRate);
  } reject:reject];
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
  [self dispatchMainWithEngineInit:^{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
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
      bool runtimeReady;
      bool added = false;
      {
        std::lock_guard<std::mutex> lock(self->_runtimeMutex);
        runtimeReady = self.runtime != nullptr;
        if (runtimeReady) {
          added = self.runtime->addSharedResource(keyStr, std::move(resource));
        }
      }

      if (!runtimeReady) {
        reject(@"E_RUNTIME_NOT_INITIALIZED", @"Audio runtime not initialized", nil);
        return;
      }
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
  } reject:reject];
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
  // unloadAudioResource does not require the audio engine to be running.
  // If the engine was never initialized, there are no resources to unload —
  // resolve immediately with NO without touching AVAudioEngine.
  if (!self.audioEngineInitialized) {
    resolve(@(NO));
    return;
  }

  // AVAudioEngine.outputNode must be accessed on the main thread to avoid
  // an RPC timeout in AURemoteIO::Cleanup when called from a background queue.
  dispatch_async(dispatch_get_main_queue(), ^{

    BOOL found = NO;
    @synchronized(self.loadedResources) {
      if ([self.loadedResources containsObject:key]) {
        [self.loadedResources removeObject:key];
        found = YES;
      }
    }

    if (found) {
      {
        std::lock_guard<std::mutex> lock(self->_runtimeMutex);
        if (self.runtime != nullptr) self.runtime->pruneSharedResources();
      }
    }

    resolve(@(found));
  });
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

#pragma mark - Event Polling Control

#ifdef RCT_NEW_ARCH_ENABLED
- (void)startEventPolling:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject
#else
RCT_EXPORT_METHOD(startEventPolling:(RCTPromiseResolveBlock)resolve
                        rejecter:(RCTPromiseRejectBlock)reject)
#endif
{
  [self startEventPolling];
  resolve(@YES);
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)stopEventPolling:(RCTPromiseResolveBlock)resolve
                 reject:(RCTPromiseRejectBlock)reject
#else
RCT_EXPORT_METHOD(stopEventPolling:(RCTPromiseResolveBlock)resolve
                       rejecter:(RCTPromiseRejectBlock)reject)
#endif
{
  if (self.eventPollTimer) {
    dispatch_source_cancel(self.eventPollTimer);
    self.eventPollTimer = nil;
  }
  resolve(@YES);
}

#ifdef RCT_NEW_ARCH_ENABLED
- (void)configureEventPolling:(double)intervalMs
                      resolve:(RCTPromiseResolveBlock)resolve
                       reject:(RCTPromiseRejectBlock)reject
#else
RCT_EXPORT_METHOD(configureEventPolling:(double)intervalMs
                        resolve:(RCTPromiseResolveBlock)resolve
                         rejecter:(RCTPromiseRejectBlock)reject)
#endif
{
  self.eventPollIntervalMs = (NSUInteger)fmax(10.0, fmin(1000.0, intervalMs));
  // If already running, restart with new interval
  if (self.eventPollTimer) {
    dispatch_source_cancel(self.eventPollTimer);
    self.eventPollTimer = nil;
    [self startEventPolling];
  }
  resolve(@YES);
}

#pragma mark - RCTEventEmitter

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"AudioPlaybackFinished", @"elementaryEvent"];
}

// Listener tracking works on both old and new arch.
// RCTEventEmitter.sendEventWithName: logs a "no listeners" warning when
// _listenerCount == 0. Our override suppresses it, and the poll timer
// also gates on _hasEventListeners to avoid needless work.
- (void)addListener:(NSString *)eventName {
  [super addListener:eventName];
  _listenerCount++;
  _hasEventListeners = YES;
}
- (void)removeListeners:(double)count {
  [super removeListeners:count];
  _listenerCount -= (int)count;
  if (_listenerCount <= 0) {
    _listenerCount = 0;
    _hasEventListeners = NO;
  }
}

// Suppress "Sending event with no listeners registered" warning.
// Events are guarded by _hasEventListeners in startEventPolling so this
// should rarely be called without listeners, but during app startup the
// processQueuedEvents timer can fire before JS has subscribed.
- (void)sendEventWithName:(NSString *)eventName body:(id)body {
  if (!_hasEventListeners) return; // silently discard
  [super sendEventWithName:eventName body:body];
}

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeElementarySpecJSI>(params);
}
#endif

@end
