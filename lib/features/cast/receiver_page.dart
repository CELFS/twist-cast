import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';

import 'receiver_view.dart';

class ReceiverPage extends StatefulWidget {
  const ReceiverPage({required this.renderer, required this.onStop,
    required this.header, super.key});
  final RTCVideoRenderer renderer;
  final VoidCallback onStop;
  final PreferredSizeWidget header;

  @override
  State<ReceiverPage> createState() => _ReceiverPageState();
}

class _ReceiverPageState extends State<ReceiverPage> {
  bool _showHeader = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _showHeader ? widget.header : null,
    body: SafeArea(child: ReceiverView(renderer: widget.renderer,
      onStop: widget.onStop, headerVisible: _showHeader,
      onToggleHeader: () => setState(() => _showHeader = !_showHeader))),
  );
}
