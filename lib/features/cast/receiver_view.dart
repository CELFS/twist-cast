import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';

import '../window/mac_window_surface.dart';
import '../../l10n/generated/app_localizations.dart';
import 'desktop_keyboard.dart';
import 'receiver_toolbar.dart';
import 'receiver_pointer.dart';

class ReceiverView extends StatefulWidget {
  const ReceiverView({required this.renderer, required this.onStop,
    required this.headerVisible, required this.onToggleHeader, this.showControls = true, this.onPointer, this.onDesktopKey, this.extraControl, this.navigation, super.key});
  final RTCVideoRenderer renderer;
  final VoidCallback onStop;
  final bool headerVisible;
  final bool showControls;
  final RemotePointer? onPointer;
  final DesktopKey? onDesktopKey;
  final Widget? extraControl;
  final Widget? navigation;
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
  bool _inspect = false;
  Offset _lastTouch = const Offset(.5, .5);
  bool get _mobile => Platform.isAndroid || Platform.isIOS;

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
          if (Platform.isMacOS) 'horizontalInset': MacWindowSurface.inset * 2,
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
    final labels = AppLocalizations.of(context);
    final desktopControl = widget.onDesktopKey != null;
    return Column(children: [
      if (widget.showControls) ReceiverToolbar(onStop: widget.onStop,
        onToggleHeader: widget.onToggleHeader, headerVisible: widget.headerVisible,
        resizeFailed: _resizeFailed, extraControl: widget.extraControl),
      if (widget.showControls) ?widget.navigation,
      if (desktopControl) Wrap(children: [
        IconButton(tooltip: _inspect ? labels.controlMode : labels.zoomMode,
          icon: Icon(_inspect ? Icons.touch_app : Icons.zoom_in),
          onPressed: () => setState(() => _inspect = !_inspect)),
        IconButton(tooltip: labels.keyboard, icon: const Icon(Icons.keyboard),
          onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true,
            builder: (_) => DesktopKeyboard(send: (key, [text]) {
              if (mounted) widget.onDesktopKey?.call(key, text);
            }))),
        for (final up in [true, false])
          IconButton(tooltip: up ? labels.scrollUp : labels.scrollDown,
            icon: Icon(up ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
            onPressed: () => widget.onPointer?.call('scroll', _lastTouch, Offset(0, up ? -.1 : .1), false)),
      ]),
      Expanded(child: LayoutBuilder(builder: (context, constraints) =>
        ValueListenableBuilder<RTCVideoValue>(valueListenable: widget.renderer, builder: (context, value, _) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          _fit(value, viewport, MediaQuery.sizeOf(context).height - viewport.height);
          final hasFrameSize = value.width > 0 && value.height > 0;
          final video = RTCVideoView(widget.renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain);
          final surface = ReceiverPointer(allowTouch: desktopControl, videoSize: Size(value.aspectRatio, 1),
            onPointer: !hasFrameSize || widget.onPointer == null || (desktopControl && _inspect) ? null
              : (action, point, scroll, landscape) {
                if (action != 'cancel') _lastTouch = point;
                widget.onPointer?.call(action, point, scroll, landscape);
              },
            child: Platform.isMacOS && hasFrameSize
              ? Center(child: AspectRatio(
                  aspectRatio: value.aspectRatio,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                    child: video,
                  ),
                ))
              : ColoredBox(color: Platform.isMacOS ? Colors.transparent : Colors.black, child: video));
          if (!_mobile) return surface;
          final inspect = !desktopControl || _inspect;
          return InteractiveViewer(panEnabled: inspect, scaleEnabled: inspect, maxScale: 5, child: surface);
        }),
      )),
    ]);
  }
}
