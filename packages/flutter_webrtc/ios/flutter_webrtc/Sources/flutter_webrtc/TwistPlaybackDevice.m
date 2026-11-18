#import "TwistPlaybackDevice.h"

@implementation TwistPlaybackDevice {
  id<RTCAudioDeviceDelegate> _delegate;
  BOOL _recording;
  BOOL _playing;
  BOOL _recordingInitialized;
  BOOL _playoutInitialized;
  NSMutableData *_pending;
  NSThread *_deliveryThread;
}
+ (instancetype)shared {
  static TwistPlaybackDevice *device;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ device = [[self alloc] init]; });
  return device;
}
- (double)deviceInputSampleRate { return 48000; }
- (double)deviceOutputSampleRate { return 48000; }
- (NSTimeInterval)inputIOBufferDuration { return 0.01; }
- (NSTimeInterval)outputIOBufferDuration { return 0.01; }
- (NSTimeInterval)inputLatency { return 0; }
- (NSTimeInterval)outputLatency { return 0; }
- (NSInteger)inputNumberOfChannels { return 1; }
- (NSInteger)outputNumberOfChannels { return 1; }
- (BOOL)isInitialized { @synchronized(self) { return _delegate != nil; } }
- (BOOL)isRecording { @synchronized(self) { return _recording; } }
- (BOOL)isPlaying { return _playing; }
- (BOOL)isRecordingInitialized { return _recordingInitialized; }
- (BOOL)isPlayoutInitialized { return _playoutInitialized; }
- (BOOL)initializeWithDelegate:(id<RTCAudioDeviceDelegate>)delegate {
  @synchronized(self) { _delegate = delegate; _pending = [NSMutableData data]; }
  return YES;
}
- (BOOL)terminateDevice {
  @synchronized(self) { _recording = NO; _delegate = nil; _pending = nil; }
  _playing = NO;
  _recordingInitialized = NO;
  _playoutInitialized = NO;
  return YES;
}
- (BOOL)initializeRecording { _recordingInitialized = YES; return YES; }
- (BOOL)initializePlayout { _playoutInitialized = YES; return YES; }
- (BOOL)startRecording { @synchronized(self) { _recording = YES; } return YES; }
- (BOOL)stopRecording { @synchronized(self) { _recording = NO; [_pending setLength:0]; } return YES; }
- (BOOL)startPlayout { _playing = YES; return YES; }
- (BOOL)stopPlayout { _playing = NO; return YES; }
- (void)appendPCM:(NSData *)data {
  // The frame reader invokes this on its dedicated socket thread. Tell the ADM
  // that delivery may move threads when a new broadcast session starts.
  id<RTCAudioDeviceDelegate> delegate;
  BOOL changedThread;
  @synchronized(self) {
    delegate = _delegate;
    if (!_recording) return;
    changedThread = _deliveryThread != NSThread.currentThread;
    _deliveryThread = NSThread.currentThread;
  }
  if (!delegate || data.length > 19200 || data.length % 2 != 0) return;
  if (changedThread) [delegate dispatchSync:^{ [delegate notifyAudioInputInterrupted]; }];
  @synchronized(self) {
    if (!_recording || delegate != _delegate) return;
    [_pending appendData:data];
    if (_pending.length > 19200) [_pending setLength:0];
    while (_pending.length >= 960) {
      int16_t samples[480];
      memcpy(samples, _pending.bytes, sizeof(samples));
      [_pending replaceBytesInRange:NSMakeRange(0, sizeof(samples)) withBytes:NULL length:0];
      AudioBufferList buffers = { .mNumberBuffers = 1,
        .mBuffers = {{ .mNumberChannels = 1, .mDataByteSize = sizeof(samples), .mData = samples }} };
      AudioTimeStamp time = {0};
      AudioUnitRenderActionFlags flags = 0;
      delegate.deliverRecordedData(&flags, &time, 0, 480, &buffers, NULL, nil);
    }
  }
}
@end
