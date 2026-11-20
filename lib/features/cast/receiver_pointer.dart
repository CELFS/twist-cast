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

class _ReceiverPointerState extends State<ReceiverPointer> {
  int? _pointer;
  Duration? _lastMove;

  void _cancel(RemotePointer? send) {
    if (_pointer == null) return;
    _pointer = null;
    _lastMove = null;
    send?.call('cancel', Offset.zero, Offset.zero, false);
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

    void send(String action, PointerEvent event, {Offset scroll = Offset.zero}) {
      final point = event.localPosition - video.topLeft;
      widget.onPointer?.call(action, Offset(
        (point.dx / video.width).clamp(0.0, 1.0),
        (point.dy / video.height).clamp(0.0, 1.0)),
        Offset(scroll.dx / video.width, scroll.dy / video.height),
        widget.videoSize.width > widget.videoSize.height);
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (_pointer != null || event.kind != PointerDeviceKind.mouse ||
            event.buttons != kPrimaryMouseButton || !video.contains(event.localPosition)) {
          return;
        }
        _pointer = event.pointer;
        send('down', event);
      },
      onPointerMove: (event) {
        if (event.pointer != _pointer) return;
        if (_lastMove != null && event.timeStamp - _lastMove! < const Duration(milliseconds: 32)) {
          return;
        }
        _lastMove = event.timeStamp;
        send('move', event);
      },
      onPointerUp: (event) {
        if (event.pointer != _pointer) return;
        _pointer = null;
        _lastMove = null;
        send('up', event);
      },
      onPointerCancel: (event) {
        if (event.pointer == _pointer) _cancel(widget.onPointer);
      },
      onPointerSignal: (event) {
        if (_pointer == null && event is PointerScrollEvent && event.scrollDelta != Offset.zero &&
            video.contains(event.localPosition)) {
          send('scroll', event, scroll: event.scrollDelta);
        }
      },
      child: widget.child,
    );
  });
}
