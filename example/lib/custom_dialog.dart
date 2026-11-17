// Custom Contacts rationale UIs for `WaPermissionGate.ensureReady`.
//
// Google Play requires a "prominent disclosure" before an app asks for the
// Contacts permission: the user must see what is accessed and why, and agree,
// before the system permission dialog appears. `ensureReady` takes care of
// this. It shows a built-in AlertDialog (in Indonesian) unless you replace it
// with your own UI in one of two ways:
//
//   1. `customWidget` + `presentation`
//      Pass a widget. The package shows it with `showDialog` or
//      `showModalBottomSheet`. Use this when the default presentation is
//      fine and you only want your own content and styling.
//      See [ContactsRationaleSheet].
//
//   2. `customDialog`
//      Pass a function that shows the UI itself and returns the user's
//      answer. Use this for full control: your own bottom sheet settings
//      (shape, colors, dismissible or not), your own route, a full page, or
//      an existing bottom sheet helper from your app.
//      See [showContactsRationaleSheet].
//
// Rules for both:
//
//   * They are shown only while the Contacts permission is not granted.
//     Once it is granted, `ensureReady` returns `true` without showing them.
//     To see them again, revoke the permission in Android Settings.
//   * The answer decides what happens next. `true` continues to the system
//     permission dialog. `false` or `null` cancels, and `ensureReady`
//     returns `false`. Closing a sheet by swiping it down or tapping outside
//     returns `null`, so it counts as cancel.
//   * Keep the disclosure text (what is accessed, why, and what happens to
//     it) visible. Without it Play Store review can reject your app update.
//
// These UIs are not for `verify(confirmOpenWhatsApp: ...)`. That callback
// runs later, during a check, and asks whether WhatsApp may be opened. See
// `confirmOpenWhatsApp` in main.dart.

import 'package:flutter/material.dart';
import 'package:wa_number_checker/wa_number_checker.dart';

/// English version of `WaPermissionRationale.defaultDisclosure`, which is in
/// Indonesian. Describes what the package does with the Contacts permission.
const contactsDisclosure =
    'The number is checked through a temporary contact in an account that '
    'belongs to this app. It is not sent to any server or saved to Google, '
    'and it is deleted after the check.';

/// Option 1: a rationale widget for `ensureReady(customWidget: ...)`.
///
/// The package shows it as configured by `presentation`. With
/// `WaPermissionPresentation.bottomSheet` it gets a drag handle, a
/// [SafeArea] and can grow up to the full screen height. With
/// `WaPermissionPresentation.dialog` it is placed in `showDialog`, so return
/// a `Dialog` or `AlertDialog` from your widget in that case.
///
/// The widget closes itself and returns the answer through the navigator:
/// `Navigator.of(context).pop(true)` to continue to the system dialog,
/// `Navigator.of(context).pop(false)` to cancel.
///
/// ```dart
/// await WaPermissionGate.ensureReady(
///   context,
///   appName: 'My App',
///   purpose: '...',
///   customWidget: const ContactsRationaleSheet(appName: 'My App'),
///   presentation: WaPermissionPresentation.bottomSheet,
/// );
/// ```
class ContactsRationaleSheet extends StatelessWidget {
  const ContactsRationaleSheet({super.key, required this.appName});

  /// Your app's name, shown in the title and the message.
  final String appName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Scrollable so the buttons stay reachable on small screens or with a
    // large font size.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.contacts_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            'Verify your WhatsApp number',
            style: textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            '$appName needs access to your contacts to check whether your '
            'number is registered on WhatsApp.',
            style: textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          // The disclosure. Keep it visible before the system dialog.
          Text(contactsDisclosure, style: textTheme.bodyMedium),
          const SizedBox(height: 24),
          FilledButton(
            // true: the package now opens the system permission dialog.
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
          const SizedBox(height: 8),
          TextButton(
            // false: ensureReady returns false, nothing else is shown.
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}

/// Option 2: a rationale function for `ensureReady(customDialog: ...)`.
///
/// Its signature must match `WaPermissionDialogBuilder`:
/// `Future<bool?> Function(BuildContext, WaPermissionRationale)`.
/// Pass the function itself (`customDialog: showContactsRationaleSheet`),
/// not the result of calling it. Calling it would open the sheet right away,
/// even when the permission is already granted.
///
/// Here the bottom sheet is configured by the app: rounded corners, a fixed
/// background color, and it cannot be dismissed by tapping outside, so the
/// user has to pick one of the buttons. `showModalBottomSheet<bool>` already
/// returns `Future<bool?>`, so its result can be returned directly.
///
/// [rationale] carries the `appName` and `purpose` passed to `ensureReady`,
/// plus the built-in `title`, `message` and `disclosure` texts (Indonesian).
///
/// If your app shows bottom sheets through a helper that does not return a
/// value (for example one with an `onClosed` callback), complete a
/// `Completer<bool>` from the buttons and from `onClosed`, and return its
/// future instead.
Future<bool?> showContactsRationaleSheet(
  BuildContext context,
  WaPermissionRationale rationale,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: ContactsRationaleSheet(appName: rationale.appName),
      ),
    ),
  );
}
