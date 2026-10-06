import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Pintu masuk izin Kontak dengan prominent disclosure milik app consumer.
///
/// Dialog sistem Android selalu menampilkan **nama app consumer**
/// otomatis — library tidak perlu (dan tidak bisa) mengaturnya.
/// Yang butuh [appName] adalah dialog penjelasan SEBELUM sistem,
/// agar terasa milik app consumer dan lolos review Play Store.
///
/// ```dart
/// final ok = await WaPermissionGate.ensureReady(
///   context,
///   appName: 'QRISKu',
///   purpose: 'memverifikasi nomor WA milikmu untuk pengiriman struk',
/// );
/// if (!ok) return; // permissionDenied — registrasi tetap boleh lanjut
/// final r = await checker.verify(phone);
/// ```
class WaPermissionGate {
  /// Tampilkan rationale (dengan [appName] consumer) lalu minta izin.
  /// Return true jika [Permission.contacts] granted.
  static Future<bool> ensureReady(
    BuildContext context, {
    required String appName,
    required String purpose,
  }) async {
    if (await Permission.contacts.isGranted) return true;
    if (!context.mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$appName butuh akses Kontak'),
        content: Text(
          '$appName perlu akses Kontak untuk $purpose.\n\n'
          'Nomor dicek lewat kontak sementara di akun khusus '
          'milik aplikasi ini (tidak dikirim ke server, tidak disimpan '
          'ke Google) dan otomatis dihapus setelah pengecekan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Nanti'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    if (proceed != true) return false;
    final res = await Permission.contacts.request();
    return res.isGranted;
  }

  /// Izin notifikasi (Android 13+) untuk notifikasi "kembali ke app"
  /// setelah WA dibuka lewat `confirmOpenWhatsApp`. Opsional: tanpa izin
  /// ini pengecekan tetap jalan, user hanya perlu kembali sendiri.
  static Future<bool> ensureNotifications() async {
    final res = await Permission.notification.request();
    return res.isGranted;
  }
}
