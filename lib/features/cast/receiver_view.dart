import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';

import 'receiver_toolbar.dart';
import 'receiver_pointer.dart';

class ReceiverView extends StatefulWidget {
  const ReceiverView({required this.renderer, required this.onStop,
    required this.headerVisible, required this.onToggleHeader, this.showControls = true, this.onPointer, this.extraControl, super.key});
  final RTCVideoRenderer renderer;
  final VoidCallback onStop;
  final bool headerVisible;
  final bool showControls;
  final RemotePointer? onPointer;
  final Widget? extraControl;
  final VoidCallback onToggleHeader;

  @override
  State<ReceiverView> createState() => _ReceiverViewState();
}

class _ReceiverViewState extends State<ReceiverView> {
  static const _window = MethodChannel('app.twist.cast/window');
  Timer? _resize;
  double? _requestedRatio;
  double? _pendingRatio;
  double? _requestedChrome;
  double? _pendingChrome;
  bool _resizeFailed = false;

  void _fit(RTCVideoValue value, Size viewport, double chromeHeight) {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux) ||
        value.width <= 0 || value.height <= 0 || viewport.isEmpty) {
      return;
    }
    final ratio = value.aspectRatio;
    if (!ratio.isFinite || ratio <= 0) return;
    if (_requestedRatio != null && (ratio - _requestedRatio!).abs() < 0.002 &&
        _requestedChrome == chromeHeight) {
      _resize?.cancel();
      _pendingRatio = null;
      return;
    }
    if (_pendingRatio != null && (ratio - _pendingRatio!).abs() < 0.002 &&
        _pendingChrome == chromeHeight) {
      return;
    }
    _resize?.cancel();
    _pendingRatio = ratio;
    _pendingChrome = chromeHeight;
    // Rotation and dimensions may arrive separately; resize once they settle.
    _resize = Timer(const Duration(milliseconds: 180), () async {
      if (!mounted) return;
      _pendingRatio = null;
      _requestedRatio = ratio;
      _requestedChrome = chromeHeight;
      try {
        await _window.invokeMethod<void>('fitVideo', {
          'aspectRatio': ratio,
          'chromeHeight': chromeHeight,
          'preferredArea': viewport.width * viewport.height,
          'minimumWidth': 320.0,
        }).timeout(const Duration(seconds: 3));
        if (mounted && _resizeFailed) setState(() => _resizeFailed = false);
      } catch (_) {
        if (mounted) setState(() => _resizeFailed = true);
      }
    });
  }

  @override
  void dispose() { _resize?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (widget.showControls) ReceiverToolbar(onStop: widget.onStop,
        onToggleHeader: widget.onToggleHeader, headerVisible: widget.headerVisible,
        resizeFailed: _resizeFailed, extraControl: widget.extraControl),
      Expanded(child: LayoutBuilder(builder: (context, constraints) =>
        ValueListenableBuilder<RTCVideoValue>(valueListenable: widget.renderer, builder: (context, value, _) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          _fit(value, viewport, MediaQuery.sizeOf(context).height - viewport.height);
          return ReceiverPointer(videoSize: Size(value.aspectRatio, 1),
            onPointer: value.width > 0 && value.height > 0 ? widget.onPointer : null,
            child: ColoredBox(color: Colors.black, child: RTCVideoView(widget.renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain)));
        }),
      )),
    ]);
  }
}
