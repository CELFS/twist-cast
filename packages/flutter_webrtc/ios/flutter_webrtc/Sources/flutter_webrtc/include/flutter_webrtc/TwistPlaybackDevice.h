#import <WebRTC/WebRTC.h>
#import <WebRTC/RTCAudioDevice.h>

/// ReplayKit PCM input. This device never opens the microphone.
@interface TwistPlaybackDevice : NSObject <RTCAudioDevice>
+ (instancetype)shared;
- (void)appendPCM:(NSData *)data;
@end
