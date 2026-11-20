import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/generated/app_localizations.dart';
import '../cast/cast_controller.dart';
import '../cast/diagnostics_card.dart';
import '../cast/receiver_page.dart';
import '../pairing/pairing_card.dart';
import '../pairing/scanner_page.dart';
import '../updates/update_card.dart';
import '../updates/update_controller.dart';
import 'app_brand.dart';
import 'app_footer.dart';

class HomePage extends StatefulWidget {
  const HomePage({required this.locale, required this.onLocaleChanged, super.key});
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _cast = CastController();
  bool _scanning = false;
  bool _installingUpdate = false;

  @override
  void dispose() { _cast.dispose(); super.dispose(); }

  Future<void> _scan() async {
    if (_scanning || _installingUpdate) return;
    _scanning = true;
    await _cast.stop();
    if (!mounted) return;
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    _scanning = false;
    if (value != null && mounted) await _cast.scanResult(value);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    final theme = Theme.of(context);
    _cast.notificationTitle = text.notificationTitle;
    _cast.notificationBody = text.notificationBody;
    return ListenableBuilder(listenable: _cast, builder: (context, _) {
      final active = ![CastPhase.idle, CastPhase.ended, CastPhase.failed].contains(_cast.phase);
      final viewing = _cast.phase == CastPhase.casting && !_cast.sending && _cast.media != null;
      final header = AppBar(title: const AppBrand(), centerTitle: false, titleSpacing: 16, actions: [
          Padding(padding: const EdgeInsets.only(right: 16), child: DropdownButton<Locale>(
            value: widget.locale, underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(value: const Locale('en'), child: Text(text.english)),
              DropdownMenuItem(value: const Locale('zh'), child: Text(text.chinese)),
            ],
            onChanged: (value) { if (value != null) widget.onLocaleChanged(value); },
          )),
        ]);
      if (viewing) {
        final media = _cast.media!;
        return ReceiverPage(renderer: media.renderer,
          onPointer: media.canSendPointer ? media.sendPointer : null,
          onStop: _cast.stop, header: header,
          canSetDisplayPower: media.canSetDisplayPower,
          diagnostics: _cast.diagnostics == null ? null : DiagnosticsCard(log: _cast.diagnostics!));
      }
      return Scaffold(
        appBar: header,
        bottomNavigationBar: const AppFooter(),
        body: SafeArea(bottom: false, child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_cast.isMobile ? text.shareTitle : text.receiveTitle, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(text.tagline, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 24),
              if (!active) ...[
                if (_cast.phase == CastPhase.failed) _Notice(text: text.sessionError, icon: Icons.error_outline),
                if (_cast.phase == CastPhase.ended) _Notice(text: text.sessionEnded, icon: Icons.check_circle_outline),
                Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Icon(_cast.isMobile ? Icons.screen_share_outlined : Icons.desktop_windows_outlined, size: 56),
                    const SizedBox(height: 20),
                    Text(text.privateHint, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    if (_cast.isMobile) ...[
                      FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: Text(text.scanQr)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(onPressed: _installingUpdate ? null : _cast.search, icon: const Icon(Icons.search), label: Text(text.findDevices)),
                    ] else
                      FilledButton.icon(onPressed: _installingUpdate ? null : _cast.receive, icon: const Icon(Icons.cast), label: Text(text.startReceiving)),
                  ],
                ))),
              ],
              if (_cast.busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
                Text(_cast.phase == CastPhase.preparing ? text.preparing : text.connecting),
              ],
              if (_cast.phase == CastPhase.receiving) Card(child: Padding(
                padding: const EdgeInsets.all(24), child: Column(children: [
                  Text(text.scanHint),
                  const SizedBox(height: 16),
                  if (_cast.qr != null) ConstrainedBox(constraints: const BoxConstraints(maxWidth: 284),
                    child: Container(color: Colors.white, padding: const EdgeInsets.all(12),
                      child: QrImageView(data: _cast.qr!, backgroundColor: Colors.white))),
                  const SizedBox(height: 12),
                  Text(text.invitationExpires),
                  if (_cast.addresses.length > 1) DropdownButton<String>(
                    value: _cast.selectedAddress,
                    items: _cast.addresses.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                    onChanged: (value) { if (value != null) _cast.selectAddress(value); },
                  ),
                  const SizedBox(height: 16),
                  Text(text.discoveryNotice, textAlign: TextAlign.center),
                ]),
              )),
              if (_cast.phase == CastPhase.searching) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
                Text(text.searchHint),
                for (final device in _cast.devices.values) Card(child: ListTile(
                  leading: const Icon(Icons.computer), title: Text(device.name),
                  trailing: const Icon(Icons.chevron_right), onTap: () => _cast.connectDevice(device),
                )),
              ],
              if (_cast.phase == CastPhase.pairing && _cast.comparison != null)
                PairingCard(code: _cast.comparison!, known: _cast.knownPeer,
                  approved: _cast.approved, onApprove: _cast.approve, onReject: _cast.stop),
              if (_cast.phase == CastPhase.casting) ...[
                _Notice(text: text.secureSession, icon: Icons.lock_outline),
                if (_cast.sending) Padding(padding: const EdgeInsets.all(24), child: Text(text.sharingHint)),
              ],
              if (_cast.media?.canEnableRemoteTouch == true) ...[
                const SizedBox(height: 16),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(text.remoteTouch),
                  subtitle: Text(text.remoteTouchHint), value: _cast.media!.remoteTouchEnabled,
                  onChanged: _cast.remoteTouchBusy ? null : _cast.setRemoteTouch),
              ],
              if (_cast.isMobile) ...[
                const SizedBox(height: 16),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(text.internalAudio),
                  subtitle: Text(text.audioHint), value: _cast.audio,
                  onChanged: _cast.audioBusy || _cast.busy ? null : _cast.setAudio),
              ],
              if (active) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(onPressed: _cast.stop, icon: const Icon(Icons.stop_circle_outlined), label: Text(text.stop)),
              ],
              const SizedBox(height: 24),
              if (_cast.diagnostics != null) DiagnosticsCard(log: _cast.diagnostics!),
              if (UpdateController.supported) ...[
                UpdateCard(sessionActive: active, onInstallingChanged: (value) {
                  if (mounted) setState(() => _installingUpdate = value);
                }),
                const SizedBox(height: 16),
              ],
            ]),
          ),
        ))),
      );
    });
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.icon});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 16),
    child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Expanded(child: Text(text))]));
}
