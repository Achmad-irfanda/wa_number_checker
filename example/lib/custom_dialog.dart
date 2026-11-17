import 'package:flutter/material.dart';
import 'package:wa_number_checker/wa_number_checker.dart';

/// Your own Contacts rationale UI, here a bottom sheet instead of the
/// built-in dialog. Pass it as `WaPermissionGate.ensureReady(customDialog:)`.
///
/// The library calls it only when the permission is not granted yet, and
/// opens the system permission dialog only when this returns `true`.
/// "Nanti", swiping the sheet down or tapping outside returns `false`/`null`.
Future<bool?> customModalBottomSheet(
  BuildContext context,
  WaPermissionRationale rationale,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        SafeArea(child: BottomSheetAutoVerifWa(rationale: rationale)),
  );
}

class BottomSheetAutoVerifWa extends StatelessWidget {
  const BottomSheetAutoVerifWa({super.key, required this.rationale});

  /// Same texts as the built-in dialog. Keep [WaPermissionRationale.disclosure]
  /// visible: Play Store review expects it before the system dialog.
  final WaPermissionRationale rationale;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rationale.title, style: textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(rationale.message, style: textTheme.bodyLarge),
          const SizedBox(height: 8),
          Text(rationale.disclosure, style: textTheme.bodyMedium),
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
