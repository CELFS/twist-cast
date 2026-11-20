import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

typedef RemotePointer = void Function(String action, Offset point,
    Offset scroll, bool landscape);

class ReceiverPointer extends StatefulWidget {
  const ReceiverPointer({required this.videoSize, required this.onPointer,
    required this.child, super.key});

  final Size videoSize;
  final RemotePointer? onPointer;
  final Widget child;

  @override
  State<ReceiverPointer> createState() => _ReceiverPointerState();
}

class _ReceiverPointerState extends State<ReceiverPointer> with WidgetsBindingObserver {
  int? _pointer;
  int? _trackpad;
  Offset? _trackpadOrigin;
  Offset? _trackpadPosition;
  Offset _trackpadPan = Offset.zero;
  Duration? _lastMove;

  bool get _hasGesture => _pointer != null || _trackpad != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancel(widget.onPointer);
  }

  void _cancel(RemotePointer? send) {
    if (!_hasGesture) return;
    final touching = _pointer != null || _trackpadPosition != null;
    _pointer = null;
    _resetTrackpad();
    if (touching) send?.call('cancel', Offset.zero, Offset.zero, false);
  }

  void _resetTrackpad() {
    _trackpad = null;
    _trackpadOrigin = null;
    _trackpadPosition = null;
    _trackpadPan = Offset.zero;
    _lastMove = null;
  }

  bool _canMove(Duration now) {
    if (_lastMove != null && now - _lastMove! < const Duration(milliseconds: 32)) return false;
    _lastMove = now;
    return true;
  }

  @override
  void didUpdateWidget(ReceiverPointer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPointer == null || widget.videoSize != oldWidget.videoSize) {
      _cancel(oldWidget.onPointer);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel(widget.onPointer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    if (widget.onPointer == null || widget.videoSize.isEmpty) return widget.child;
    final size = constraints.biggest;
    final video = Alignment.center.inscribe(
      applyBoxFit(BoxFit.contain, widget.videoSize, size).destination, Offset.zero & size);
    if (video.isEmpty) return widget.child;

    void send(String action, Offset position, {Offset scroll = Offset.zero}) {
      final point = position - video.topLeft;
      widget.onPointer?.call(action, Offset(
        (point.dx / video.width).clamp(0.0, 1.0),
        (point.dy / video.height).clamp(0.0, 1.0)),
        Offset(scroll.dx / video.width, scroll.dy / video.height),
        widget.videoSize.width > widget.videoSize.height);
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (_hasGesture || event.kind != PointerDeviceKind.mouse ||
            event.buttons != kPrimaryMouseButton || !video.contains(event.localPosition)) {
          return;
        }
        _pointer = event.pointer;
        send('down', event.localPosition);
      },
      onPointerMove: (event) {
        if (event.pointer != _pointer) return;
        if (_canMove(event.timeStamp)) send('move', event.localPosition);
      },
      onPointerUp: (event) {
        if (event.pointer != _pointer) return;
        _pointer = null;
        _lastMove = null;
        send('up', event.localPosition);
      },
      onPointerCancel: (event) {
        if (event.pointer == _pointer) _cancel(widget.onPointer);
      },
      onPointerPanZoomStart: (event) {
        final state = WidgetsBinding.instance.lifecycleState;
        if (_hasGesture || (state != null && state != AppLifecycleState.resumed) ||
            !video.contains(event.localPosition)) {
          return;
        }
        _trackpad = event.pointer;
        _trackpadOrigin = event.localPosition;
      },
      onPointerPanZoomUpdate: (event) {
        if (event.pointer != _trackpad) return;
        if (event.scale != 1 || event.rotation != 0) {
          _cancel(widget.onPointer);
          return;
        }
        final origin = _trackpadOrigin!;
        _trackpadPan += event.localPanDelta;
        if (_trackpadPosition == null) {
          if (_trackpadPan.distance < 3) return;
          send('down', origin);
        }
        final position = origin + _trackpadPan;
        _trackpadPosition = position;
        if (_canMove(event.timeStamp)) send('move', position);
      },
      onPointerPanZoomEnd: (event) {
        if (event.pointer != _trackpad) return;
        final position = _trackpadPosition;
        _resetTrackpad();
        if (position != null) send('up', position);
      },
      onPointerSignal: (event) {
        if (!_hasGesture && event is PointerScrollEvent && event.scrollDelta != Offset.zero &&
            video.contains(event.localPosition)) {
          send('scroll', event.localPosition, scroll: event.scrollDelta);
        }
      },
      child: widget.child,
    );
  });
}
