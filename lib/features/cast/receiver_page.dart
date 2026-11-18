import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import 'receiver_toolbar.dart';
import 'receiver_view.dart';

class ReceiverPage extends StatefulWidget {
  const ReceiverPage({required this.renderer, required this.onStop,
    required this.header, this.diagnostics, super.key});
  final RTCVideoRenderer renderer;
  final VoidCallback onStop;
  final PreferredSizeWidget header;
  final Widget? diagnostics;

  @override
  State<ReceiverPage> createState() => _ReceiverPageState();
}

class _ReceiverPageState extends State<ReceiverPage> {
  static const _window = MethodChannel('app.twist.cast/window');
  bool _showHeader = false;
  bool _nativeControls = false;
  String? _controlsLabel;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _window.setMethodCallHandler((call) async {
        if (call.method == 'toggleReceiverControls' && mounted) {
          setState(() => _showHeader = !_showHeader);
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final label = AppLocalizations.of(context).receiverControls;
    if (Platform.isMacOS && _controlsLabel != label) {
      _controlsLabel = label;
      _configureTitlebar(label);
    }
  }

  Future<void> _configureTitlebar(String label) async {
    try {
      final enabled = await _window.invokeMethod<bool>('receiverControls', {
        'enabled': true, 'label': label,
      }).timeout(const Duration(seconds: 3));
      if (mounted) setState(() => _nativeControls = enabled == true);
    } catch (_) {
      // Keep the existing controls available if the native titlebar is unavailable.
    }
  }

  @override
  void dispose() {
    if (Platform.isMacOS) {
      _window.setMethodCallHandler(null);
      _window.invokeMethod<void>('receiverControls', {'enabled': false}).catchError((Object _) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: !_nativeControls && _showHeader ? widget.header : null,
    body: SafeArea(child: Stack(children: [
      Positioned.fill(child: ReceiverView(renderer: widget.renderer,
        onStop: widget.onStop, headerVisible: _showHeader, showControls: !_nativeControls,
        onToggleHeader: () => setState(() => _showHeader = !_showHeader))),
      if (_nativeControls && _showHeader) ...[
        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showHeader = false))),
        Align(alignment: Alignment.topRight, child: Padding(
          padding: const EdgeInsets.all(8),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440),
            child: CallbackShortcuts(bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () => setState(() => _showHeader = false),
            }, child: Focus(autofocus: true, child: Card(clipBehavior: Clip.antiAlias, child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: widget.header.preferredSize.height, child: widget.header),
                ReceiverToolbar(onStop: widget.onStop, headerVisible: true,
                  onToggleHeader: () => setState(() => _showHeader = false)),
                if (widget.diagnostics != null) widget.diagnostics!,
              ],
            )))),
          ),
        )),
      ],
    ])),
  );
}
