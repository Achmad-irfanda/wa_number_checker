// wa_number_checker example
//
// Shows the recommended integration: a manual "Check and Verify" button.
//
// How a check works (Android only, iOS always returns `unsupported`):
//
//   1. Local lookup. If WhatsApp has already marked the number in the device
//      contacts, the result is `registered` immediately. Nothing is inserted
//      and WhatsApp is not opened.
//   2. Otherwise the library stores the number as a hidden contact in its own
//      account and waits for WhatsApp to mark it.
//   3. WhatsApp only looks up new contacts while it is on screen, so the
//      library can open it for you (see [confirmOpenWhatsApp]). While the
//      user is in WhatsApp a progress notification is shown; it turns into a
//      result notification as soon as the answer is known. Tapping it brings
//      the user back here.
//   4. `verify()` completes with the result. If WhatsApp was opened and the
//      number did not show up before the timeout, the result is
//      `notRegistered`.
//
// Checked numbers stay cached on the device (up to 100), so checking the same
// registered number again finishes at step 1.

import 'package:flutter/material.dart';
import 'package:wa_number_checker/wa_number_checker.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wa_number_checker example',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const ExampleHome(),
    );
  }
}

class ExampleHome extends StatefulWidget {
  const ExampleHome({super.key});

  @override
  State<ExampleHome> createState() => _ExampleHomeState();
}

class _ExampleHomeState extends State<ExampleHome> {
  late final WaNumberChecker checker;
  final phoneCtrl = TextEditingController(text: '08');

  /// Result of the last check, or null if the number changed since then.
  WaCheckResult? result;

  /// Device state shown in the log section (WhatsApp installed/active, etc.).
  WaDeviceInfo? info;

  /// True while a check is running; disables the button.
  bool checking = false;

  @override
  void initState() {
    super.initState();
    // Create one checker and reuse it. The defaults are used here; pass a
    // `WaCheckerConfig` to change them, for example:
    //
    //   WaNumberChecker(
    //     config: const WaCheckerConfig(
    //       // How long to wait after WhatsApp was opened (default 15s).
    //       openWhatsAppTimeout: Duration(seconds: 15),
    //       // How many checked numbers to keep cached (default 100).
    //       maxStoredContacts: 100,
    //       // Notification texts (defaults are in Indonesian).
    //       progressNoticeTitle: 'Verifying WhatsApp number…',
    //       returnNoticeTitle: 'Verification finished',
    //       notRegisteredNoticeTitle: 'Not a WhatsApp number',
    //     ),
    //   );
    checker = WaNumberChecker();
  }

  @override
  void dispose() {
    // Stops any running check and releases the contacts observer.
    checker.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  /// Turns a result into the text shown under the input field.
  ///
  /// Only `registered` and `notRegistered` are definite answers. Every other
  /// status means the check could not be completed, so do not treat those as
  /// "invalid number".
  String label(WaCheckResult? r) => switch (r?.status) {
    null => 'Type a number, then tap Check and Verify',
    WaCheckStatus.registered =>
      '✓ WA detected (${r!.detectedBy.map((e) => e.name).join(', ')})',
    WaCheckStatus.notRegistered =>
      '⚠ Number is not registered on WA, double-check it',
    WaCheckStatus.pending => '… could not be determined (pending/timeout)',
    WaCheckStatus.offline => '… offline — check was not run',
    WaCheckStatus.waNotInstalled => '… WA is not installed on this device',
    WaCheckStatus.waNotActive => '… WA is installed but not logged in',
    WaCheckStatus.permissionDenied => '… Contacts permission not granted',
    WaCheckStatus.unsupported => '… platform not supported (iOS)',
    WaCheckStatus.storageBlocked => '… storage blocked by ROM policy',
    WaCheckStatus.cancelled => '… cancelled',
  };

  Future<void> loadInfo() async {
    final i = await checker.getDeviceInfo();
    if (mounted) setState(() => info = i);
  }

  /// Step 1 for every app: ask for the Contacts permission.
  ///
  /// The library never requests permissions on its own. `ensureReady` shows
  /// an explanation dialog with your app name first (required by Play Store
  /// for contacts access), then the system permission dialog. Without this
  /// permission `verify()` returns `permissionDenied`.
  Future<void> ensure() async {
    await WaPermissionGate.ensureReady(
      context,
      appName: 'App Checker WhatsApp',
      // Shown inside the explanation dialog, which is in Indonesian.
      purpose: 'memverifikasi nomor WA milikmu untuk demo ini',
    );
    await loadInfo();
  }

  /// Asks the user whether WhatsApp may be opened for this check.
  ///
  /// The library calls this only when the local lookup found nothing, so
  /// users are not interrupted for numbers that are already known.
  ///
  /// Return `true` to open WhatsApp, or `false` to check without opening it.
  /// Without opening WhatsApp a new number usually ends as `pending`.
  Future<bool> confirmOpenWhatsApp() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Open WhatsApp briefly?'),
        content: const Text(
          'WhatsApp on this device does not know this number yet. We will '
          'open WhatsApp for a few seconds to verify it.\n\n'
          'A notification shows the progress. Tap it when it is finished '
          'to come back to this app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Open WhatsApp'),
          ),
        ],
      ),
    );
    if (ok != true) return false;

    // Ask for the notification permission right when it is needed (Android
    // 13+). It is optional: if the user declines, the check still runs, but
    // no notification appears and the user has to switch back manually.
    await WaPermissionGate.ensureNotifications();
    return true;
  }

  /// Runs one check for the number in the text field.
  ///
  /// `verify()` does the whole flow described at the top of this file and
  /// completes as soon as the answer is known. It keeps running while the
  /// user is in WhatsApp, so the result is already here when they return.
  Future<void> checkNow() async {
    setState(() => checking = true);
    final r = await checker.verify(
      phoneCtrl.text.trim(), // Accepts 08xx, 62xx and +62xx.
      // Leave this out if your app must never open WhatsApp.
      confirmOpenWhatsApp: confirmOpenWhatsApp,
    );
    print("result $r");
    if (mounted) setState(() => result = r);
    setState(() => checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('wa_number_checker demo'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Form checker  (manual)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            // Checks are started by the button only. Typing just clears the
            // previous result so it is not mistaken for the new number's.
            onChanged: (_) {
              if (result != null) setState(() => result = null);
            },
            decoration: const InputDecoration(
              labelText: 'Nomor WA (08xx / +62 / 62)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(label(result)),
          SizedBox(height: 10),
          Center(
            child: Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: ensure,
                  child: const Text('Permissions'),
                ),
                ElevatedButton(
                  onPressed: checking ? null : checkNow,
                  child: const Text(' Check and Verify'),
                ),
              ],
            ),
          ),

          // Debug details. A real app does not need to show these.
          SizedBox(height: 20),
          Text(
            "Log tracking result:",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
          ),
          if (info != null)
            Text(
              'installed=${info!.installedApps.map((e) => e.name).toList()} '
              'active=${info!.activeApps.map((e) => e.name).toList()} '
              'online=${info!.online} powerSave=${info!.powerSave}',
              style: const TextStyle(fontSize: 12),
            ),
          if (result != null) ...[
            const SizedBox(height: 8),
            // `latencyMs` is set when the number was detected after an
            // insert. `hints` explains how the check ran, for example
            // `waOpened` or `rateLimited`.
            Text(
              'latency=${result!.latencyMs}ms hints=${result!.hints}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
