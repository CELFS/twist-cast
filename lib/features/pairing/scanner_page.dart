import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/generated/app_localizations.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _returned = false;

  @override
  void dispose() { _scanner.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(text.scanQr)),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(24), child: Text(text.scanHint)),
        Expanded(child: MobileScanner(
          controller: _scanner,
          errorBuilder: (context, error) => Center(child: Text(text.cameraError)),
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final value = barcode.rawValue;
              if (!_returned && value != null) {
                _returned = true;
                Navigator.of(context).pop(value);
                return;
              }
            }
          },
        )),
      ]),
    );
  }
}
