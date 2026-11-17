import 'package:flutter/material.dart';
import 'package:wa_number_checker/wa_number_checker.dart';

/// Your own Contacts rationale UI, built entirely by the app. Pass it as
/// `WaPermissionGate.ensureReady(customWidget: ...)` with
/// `presentation: WaPermissionPresentation.bottomSheet`; the library shows
/// it only when the permission is not granted yet.
///
/// Close it with `Navigator.of(context).pop(true)` to continue to the system
/// permission dialog, or `pop(false)` to cancel. Swiping the sheet down or
/// tapping outside also cancels.
class BottomSheetAutoVerifWa extends StatelessWidget {
  const BottomSheetAutoVerifWa({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.contacts_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            'Verifikasi nomor WhatsApp',
            style: textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'App Checker WhatsApp perlu akses Kontak untuk memverifikasi '
            'nomor WA milikmu.',
            style: textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          // Keep this text visible: Play Store review expects it before the
          // system permission dialog.
          Text(
            WaPermissionRationale.defaultDisclosure,
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Lanjutkan'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Nanti'),
          ),
        ],
      ),
    );
  }
}
