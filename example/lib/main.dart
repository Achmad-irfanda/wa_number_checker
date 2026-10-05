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
  WaInputValidator? validator;
  final phoneCtrl = TextEditingController(text: '08');
  WaCheckResult? live;
  WaCheckResult? manual;
  WaDeviceInfo? info;
  bool checking = false;

  @override
  void initState() {
    super.initState();
    checker = WaNumberChecker();
    validator = WaInputValidator(
      checker: checker,
      onResult: (r) => mounted ? setState(() => live = r) : null,
    );
  }

  @override
  void dispose() {
    validator?.dispose();
    checker.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  String label(WaCheckResult? r) => switch (r?.status) {
    null => 'Type a number — result appears automatically',
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

  Future<void> ensure() async {
    await WaPermissionGate.ensureReady(
      context,
      appName: 'App Checker WhatsApp',
      purpose: 'memverifikasi nomor WA milikmu untuk demo ini',
    );
    await loadInfo();
  }

  Future<void> checkNow() async {
    setState(() => checking = true);
    final r = await checker.verify(phoneCtrl.text.trim());
    if (mounted) setState(() => manual = r);
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
            'Form checker  (live, non-blocking)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            onChanged: validator?.onChanged,
            decoration: const InputDecoration(
              labelText: 'Nomor WA (08xx / +62 / 62)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(label(live)),
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
          if (manual != null) ...[
            const SizedBox(height: 8),
            Text('Manual: ${label(manual)}'),
            Text(
              'latency=${manual!.latencyMs}ms hints=${manual!.hints}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
