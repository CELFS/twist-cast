import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import 'cast_media.dart';

typedef DesktopKey = void Function(String key, [String? text]);

class DesktopKeyboard extends StatefulWidget {
  const DesktopKeyboard({required this.send, super.key});
  final DesktopKey send;

  @override
  State<DesktopKeyboard> createState() => _DesktopKeyboardState();
}

class _DesktopKeyboardState extends State<DesktopKeyboard> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = AppLocalizations.of(context);
    void submit() {
      if (_text.text.isEmpty || _text.text.length > 256) return;
      widget.send('text', _text.text);
      _text.clear();
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.viewInsetsOf(context).bottom + 12),
      child: SafeArea(top: false, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(child: TextField(controller: _text, autofocus: true,
              decoration: InputDecoration(labelText: labels.typeText),
              maxLength: 256, onSubmitted: (_) => submit())),
            IconButton(tooltip: labels.sendText, icon: const Icon(Icons.send), onPressed: submit),
          ]),
          Wrap(children: [
            for (final key in CastMedia.desktopKeys)
              TextButton(onPressed: () => widget.send(key), child: Text(
                const {'Left': '←', 'Right': '→', 'Up': '↑', 'Down': '↓'}[key] ?? key)),
          ]),
        ],
      ))),
    );
  }
}
