import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

class PairingCard extends StatelessWidget {
  const PairingCard({required this.code, required this.known,
    required this.approved, required this.onApprove, required this.onReject, super.key});
  final String code;
  final bool known;
  final bool approved;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    return Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.verified_user_outlined, size: 36),
        const SizedBox(height: 16),
        Text(known ? text.knownDevice : text.verifyDevices, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(text.compareHint),
        Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: SelectableText(
          code, textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontFamily: 'monospace'),
        )),
        FilledButton(onPressed: approved ? null : onApprove,
          child: Text(approved ? text.waitingApproval : text.codesMatch)),
        TextButton(onPressed: onReject, child: Text(text.reject)),
      ],
    )));
  }
}
