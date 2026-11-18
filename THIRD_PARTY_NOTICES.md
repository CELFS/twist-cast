# Third-party notices

TwistCast includes a locally maintained copy of flutter_webrtc 1.6.3 under `packages/flutter_webrtc`. Its original code, embedded third-party code, and local modifications retain their applicable licenses. TwistCast's root MIT license does not replace third-party licenses or copyright notices.

## Included source code

Paths in the following table are relative to `packages/flutter_webrtc/`.

| Component or source files | Copyright and attribution | License materials |
| --- | --- | --- |
| flutter_webrtc, except files with their own notices | Copyright (c) 2018 湖北捷智云技术有限公司 | [MIT license](packages/flutter_webrtc/LICENSE); [original upstream NOTICE](packages/flutter_webrtc/NOTICE) |
| react-native-webrtc-derived code identified by the upstream NOTICE, including the iOS broadcast integration | Copyright (c) 2015 Howard Yang; retain individual source attributions | MIT text and attribution in the [original upstream NOTICE](packages/flutter_webrtc/NOTICE) |
| `linux/flutter/**`, `common/cpp/include/task_runner.h`, `windows/task_runner_windows.cc`, `windows/task_runner_windows.h`, `android/src/main/java/com/cloudwebrtc/webrtc/video/camera/CameraRegionUtils.java`, and `android/src/main/java/com/cloudwebrtc/webrtc/video/camera/SdkCapabilityChecker.java` | The Flutter Authors; retain the copyright years in each source file | [Flutter BSD license](packages/flutter_webrtc/third_party/licenses/flutter/LICENSE) |
| `common/darwin/Classes/media_stream_interface.h` and its copy under `ios/flutter_webrtc/Sources/flutter_webrtc/include/flutter_webrtc/` | Copyright 2012 The WebRTC project authors. All Rights Reserved. | [WebRTC BSD license](packages/flutter_webrtc/third_party/licenses/webrtc/LICENSE); [additional patent grant](packages/flutter_webrtc/third_party/licenses/webrtc/PATENTS); [upstream authors](packages/flutter_webrtc/third_party/licenses/webrtc/AUTHORS) |
| `android/src/main/java/org/webrtc/HighSpeedCamera2Capturer.java` and `HighSpeedCamera2Session.java` | Copyright 2026 The livekit-app authors. | These file headers specify the [BSD-style license used by WebRTC](packages/flutter_webrtc/third_party/licenses/webrtc/LICENSE) |
| `android/src/main/java/com/cloudwebrtc/webrtc/SimulcastVideoEncoderFactoryWrapper.kt` | Copyright 2017, Lyo Kato &lt;lyo.kato at gmail.com&gt; (Original Author); Copyright 2017-2021, Shiguredo Inc. | [Apache License 2.0](packages/flutter_webrtc/third_party/licenses/apache/LICENSE-2.0.txt); attribution in the [original upstream NOTICE](packages/flutter_webrtc/NOTICE) |
| `android/src/main/java/org/webrtc/Camera1Helper.java` and `Camera2Helper.java` | Copyright 2023-2024 LiveKit, Inc. | [Apache License 2.0](packages/flutter_webrtc/third_party/licenses/apache/LICENSE-2.0.txt); original notices remain in both files |
| Modifications in `android/src/main/java/com/cloudwebrtc/webrtc/record/VideoFileRenderer.java` | Modifications by Signify, Copyright 2025, Signify Holding | MIT, as declared by the source file's SPDX identifier; retain this attribution with the [MIT terms](packages/flutter_webrtc/LICENSE) |
| `third_party/svpng/` | Copyright (C) 2017 Milo Yip. All rights reserved. | [Original BSD-style license](packages/flutter_webrtc/third_party/svpng/LICENSE) |

The full license block in `svpng.hpp` and its accompanying LICENSE contain BSD-style redistribution conditions. A separate documentation annotation in that header says MIT; this index follows the full license text and preserves both original files unchanged.

The [native integration notes](packages/flutter_webrtc/TWISTCAST_PATCHES.md) describe the local capture changes. Original copyright headers and the upstream NOTICE are retained. This index supplements those notices rather than replacing or relicensing them.

## Sources and verification

The following legal documents were retrieved unchanged from their upstream sources on 2026-11-18. Commit references identify the snapshots used for the legal materials; they do not claim that every embedded source file originated at that same commit. The flutter_webrtc LICENSE and NOTICE were also checked against the installed 1.6.3 package.

| Local document | Upstream source | SHA-256 |
| --- | --- | --- |
| [NOTICE](packages/flutter_webrtc/NOTICE) | [Upstream text](https://raw.githubusercontent.com/flutter-webrtc/flutter-webrtc/63d95f79b06ff04cb17eb871d851045f91efcaf0/NOTICE) | `8011f1d65f669712da37c11983bb6d4063e6b3b4068b220dec24518583d733f0` |
| [third_party/licenses/flutter/LICENSE](packages/flutter_webrtc/third_party/licenses/flutter/LICENSE) | [Upstream text](https://raw.githubusercontent.com/flutter/flutter/ab2912035e160d9cad6306df307576da6128ebdb/LICENSE) | `a598db94b6290ffbe10b5ecf911057b6a943351c727fdda9e5f2891d68700a20` |
| [third_party/licenses/webrtc/LICENSE](packages/flutter_webrtc/third_party/licenses/webrtc/LICENSE) | [Upstream text](https://raw.githubusercontent.com/webrtc-sdk/webrtc/4de68c8241d1c04d866aa1efd64f0be71317ad79/LICENSE) | `ab00a482b6a3902e40211b43c5d0441962ea99b6cc7c25c0f243fa270b78d482` |
| [third_party/licenses/webrtc/PATENTS](packages/flutter_webrtc/third_party/licenses/webrtc/PATENTS) | [Upstream text](https://raw.githubusercontent.com/webrtc-sdk/webrtc/4de68c8241d1c04d866aa1efd64f0be71317ad79/PATENTS) | `01462e2068d1a04c2274f3389773014c14ed9bc3446b28303543bd3e3c064145` |
| [third_party/licenses/webrtc/AUTHORS](packages/flutter_webrtc/third_party/licenses/webrtc/AUTHORS) | [Upstream text](https://raw.githubusercontent.com/webrtc-sdk/webrtc/4de68c8241d1c04d866aa1efd64f0be71317ad79/AUTHORS) | `0d111130ece163ae3d65918344ebdbdba5072135c0447eed1d71804753e1b9cd` |
| [third_party/licenses/apache/LICENSE-2.0.txt](packages/flutter_webrtc/third_party/licenses/apache/LICENSE-2.0.txt) | [Upstream text](https://www.apache.org/licenses/LICENSE-2.0.txt) | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |

## Distribution scope

This index covers the third-party source copied into `packages/flutter_webrtc`. Keep it, the linked license files, the upstream NOTICE, and the applicable source copyright headers with source distributions.

Builds also obtain Dart packages and native SDKs through their dependency managers. When distributing an APK, app bundle, or desktop binary, include the license and attribution materials for the actual dependencies in that build, including the native WebRTC SDK's bundled third-party components. Flutter's generated package-license collection and this source index are not, by themselves, a complete inventory of every native binary dependency. Any original third-party NOTICE files and applicable patent grants must remain available with the distribution.
