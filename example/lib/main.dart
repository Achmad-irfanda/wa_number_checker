import 'package:flutter/material.dart';
import 'package:wa_number_checker/wa_number_checker.dart';

void main() => runApp(const ExampleApp());

/// Demo 2 mode: form registrasi (lapis simpel, `onChanged`-aman) +
/// dashboard advance (device info + check manual).
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
    null => 'Ketik nomor — hasil muncul otomatis',
    WaCheckStatus.registered =>
      '✓ WA terdeteksi (${r!.detectedBy.map((e) => e.name).join(', ')})',
    WaCheckStatus.notRegistered =>
      '⚠ Nomor tidak terdaftar di WA, pastikan benar',
    WaCheckStatus.pending => '… belum bisa dipastikan (pending/timeout)',
    WaCheckStatus.offline => '… offline — pengecekan tidak dijalankan',
    WaCheckStatus.waNotInstalled => '… WA tidak terinstal di device ini',
    WaCheckStatus.waNotActive => '… WA terinstal tapi belum login',
    WaCheckStatus.permissionDenied => '… izin Kontak belum diberikan',
    WaCheckStatus.unsupported => '… platform tidak didukung (iOS)',
    WaCheckStatus.storageBlocked => '… penyimpanan diblokir ROM',
    WaCheckStatus.cancelled => '… dibatalkan',
  };

  Future<void> loadInfo() async {
    final i = await checker.getDeviceInfo();
    if (mounted) setState(() => info = i);
  }

  Future<void> ensure() async {
    await WaPermissionGate.ensureReady(
      context,
      appName: 'Contoh Registrasi',
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
      appBar: AppBar(title: const Text('wa_number_checker example')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Form registrasi (live, non-blocking — tombol Daftar tetap aktif)',
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
          const Divider(),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: ensure,
                child: const Text('1. Izin + Device info'),
              ),
              ElevatedButton(
                onPressed: checking ? null : checkNow,
                child: const Text('2. Verify sekarang'),
              ),
            ],
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
