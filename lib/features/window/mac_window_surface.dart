import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class MacWindowSurface extends StatelessWidget {
  const MacWindowSurface({required this.child, super.key});

  static const inset = 6.0;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) return child;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: LinearGradient(
        colors: [Color(0xFFE2E8E8), Color(0xFFD9E2E1), Color(0xFFC7D7E1)],
      )),
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: RadialGradient(
          center: Alignment(-1, -0.76), radius: 0.9,
          colors: [Color(0xFFE0DFE5), Color(0x00E0DFE5)],
        )),
        child: child,
      ),
    );
  }
}

class MacWindowTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const MacWindowTitleBar({this.actions = const [], super.key}) : _height = 38;
  const MacWindowTitleBar.receiver({super.key}) : actions = const [], _height = 22;

  static const _window = MethodChannel('app.twist.cast/window');
  final double _height;
  final List<Widget> actions;

  @override
  Size get preferredSize => Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: _height,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    flexibleSpace: Padding(
      padding: EdgeInsets.only(left: 84, right: actions.isEmpty ? 84 : 120),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons == kPrimaryMouseButton) {
            _window.invokeMethod<void>('startWindowDrag').catchError((Object _) {});
          }
        },
        child: const SizedBox.expand(),
      ),
    ),
    actions: actions,
  );
}
