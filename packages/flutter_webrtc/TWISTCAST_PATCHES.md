# TwistCast native integration

Base: flutter_webrtc 1.6.3 (MIT). Upstream source and license are retained.

Android changes provide internal playback capture with Android's AudioPlaybackCapture API and WebRTC's external audio buffer callback. The WebRTC microphone recorder is disabled. The screen and audio share one MediaProjection grant. Capture is stopped when permission is revoked or the session ends. Audio remains subject to the source application's capture policy.

The external audio callback paces both captured and silent PCM buffers by their sample duration. Waiting occurs outside the recorder lock, and missed deadlines are discarded instead of delivering a burst of queued frames. Failed recorder startup releases the recorder before reporting the error.

The application uses this local package so a clean checkout reproduces the same capture behavior without modifying the global package cache.

The iOS integration adds `TwistPlaybackDevice`, supplies the broadcast stream with an audio track, and extends the App Group socket reader to accept 48 kHz mono PCM. The main application's ReplayKit extension is located in `ios/BroadcastExtension`. Socket closure is reported to the application so the session can end. iOS source and project structure have not yet been validated by a full Xcode build or a device broadcast session.
