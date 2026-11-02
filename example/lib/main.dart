// wa_number_checker example
//
// Shows the recommended integration: a manual "Check and Verify" button.
//
// How a check works (Android only, other platforms always return `unsupported`):
//
//   1. Local lookup. If WhatsApp has already marked the number in the device
//      contacts, the result is `registered` immediately. Nothing is inserted
//      and WhatsApp is not opened.
//   2. Otherwise the library stores the number as a hidden contact in its own
//      account and waits for WhatsApp to mark it.
//   3. WhatsApp only looks up new contacts while it is on screen, so the
//      library can open it for you (see [confirmOpenWhatsApp]). While the
//      user is in WhatsApp a progress notification is shown; it turns into a
//      result notification as soon as the answer is known. Its button brings
//      the user back here; after 4.5s the library also tries that by itself.
//   4. `verify()` completes with the result. If the number did not show up
//      before the timeout (8s), the result is `pending`. WhatsApp may need
//      longer on a cold start, so offer another check.
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
  late WaNumberChecker checker;
  final phoneCtrl = TextEditingController(text: '08');
  WaNoticeStyle noticeStyle = WaNoticeStyle.standard;

  /// Result of the last check, or null if the number changed since then.
  WaCheckResult? result;

  /// Device state shown in the log section (WhatsApp installed/active, etc.).
  WaDeviceInfo? info;

  /// True while a check is running; disables the button.
  bool checking = false;

  /// True once the user allowed this app to draw over other apps.
  bool overlayGranted = false;

  /// The overlay permission is granted in Settings, not in a dialog, so it is
  /// read again whenever the user comes back to this app.
  late final AppLifecycleListener lifecycle;

  @override
  void initState() {
    super.initState();
    _initChecker();
    lifecycle = AppLifecycleListener(onResume: loadOverlayState);
    loadOverlayState();
  }

  void _initChecker() {
    checker = WaNumberChecker(
      config: WaCheckerConfig(
        noticeStyle: noticeStyle,
        returnActionText: 'back to client app',
      ),
    );
  }

  @override
  void dispose() {
    // Stops any running check and releases the contacts observer.
    lifecycle.dispose();
    checker.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  /// Turns a result into the text shown under the input field.
  ///
  /// Only `registered` is a definite answer. Every other status means the
  /// number could not be confirmed, so do not treat those as "invalid number".
  String label(WaCheckResult? r) => switch (r?.status) {
    null => 'Type a number, then tap Check and Verify',
    WaCheckStatus.registered =>
      '✓ WA detected (${r!.detectedBy.map((e) => e.name).join(', ')})',
    WaCheckStatus.notRegistered =>
      '⚠ Number is not registered on WA, double-check it',
    WaCheckStatus.pending => '… could not be determined, tap to check again',
    WaCheckStatus.offline => '… offline — check was not run',
    WaCheckStatus.waNotInstalled => '… WA is not installed on this device',
    WaCheckStatus.waNotActive => '… WA is installed but not logged in',
    WaCheckStatus.permissionDenied => '… Contacts permission not granted',
    WaCheckStatus.unsupported => '… platform not supported (Android only)',
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

  Future<void> loadOverlayState() async {
    final granted = await checker.canDrawOverlays();
    if (mounted) setState(() => overlayGranted = granted);
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
          'A notification shows the result. Tap its button to come back '
          'to this app; if WhatsApp was just starting, check again.',
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
    if (mounted) setState(() => result = r);
    setState(() => checking = false);
  }

  /// Opens WhatsApp without asking and shows the progress and the result in
  /// a card on top of it, instead of notifications.
  ///
  /// WhatsApp stays closed when the number is already known on this device,
  /// because the local lookup answers first.
  Future<void> checkWithOverlay() async {
    setState(() => checking = true);
    final r = await checker.verify(
      phoneCtrl.text.trim(),
      confirmOpenWhatsApp: () async => true,
      useOverlay: true,
    );
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
          const SizedBox(height: 12),
          const Text(
            'Notification Style:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          SegmentedButton<WaNoticeStyle>(
            segments: const [
              ButtonSegment(
                value: WaNoticeStyle.standard,
                label: Text('Style A (Standard)'),
              ),
              ButtonSegment(
                value: WaNoticeStyle.custom,
                label: Text('Style B (Custom Layout)'),
              ),
            ],
            selected: {noticeStyle},
            onSelectionChanged: (val) {
              setState(() {
                noticeStyle = val.first;
                checker.dispose();
                _initChecker();
              });
            },
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 14),
          const Text(
            'Alert window:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Center(
            child: Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  // Opens Settings: find this app and allow it there.
                  onPressed: checker.openOverlaySettings,
                  child: Text(
                    overlayGranted ? 'Overlay allowed ✓' : 'Allow Overlay',
                  ),
                ),
                ElevatedButton(
                  onPressed: checking || !overlayGranted
                      ? null
                      : checkWithOverlay,
                  child: const Text('Open WA + Overlay'),
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
