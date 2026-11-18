import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Teks penjelasan izin Kontak yang dipakai dialog bawaan
/// [WaPermissionGate.ensureReady].
///
/// Diteruskan ke [WaPermissionDialogBuilder] agar UI custom bisa memakai
/// teks yang sama, terutama [disclosure] yang dibutuhkan untuk prominent
/// disclosure Play Store.
class WaPermissionRationale {
  const WaPermissionRationale({required this.appName, required this.purpose});

  /// Nama app consumer, dari `ensureReady(appName: ...)`.
  final String appName;

  /// Tujuan akses Kontak, dari `ensureReady(purpose: ...)`.
  final String purpose;

  /// Contoh: "QRISKu butuh akses Kontak".
  String get title => '$appName butuh akses Kontak';

  /// Contoh: "QRISKu perlu akses Kontak untuk memverifikasi nomor WA ...".
  String get message => '$appName perlu akses Kontak untuk $purpose.';

  /// Cara library memakai Kontak. Tampilkan juga di UI custom.
  String get disclosure => defaultDisclosure;

  /// Sama dengan [disclosure], untuk widget custom yang tidak menerima
  /// [WaPermissionRationale] (lihat `ensureReady(customWidget: ...)`).
  static const String defaultDisclosure =
      'Nomor dicek lewat kontak sementara di akun khusus '
      'milik aplikasi ini (tidak dikirim ke server, tidak disimpan '
      'ke Google) dan otomatis dihapus setelah pengecekan.';
}

/// Cara library menampilkan `ensureReady(customWidget: ...)`.
enum WaPermissionPresentation {
  /// Lewat `showDialog`. Widget sebaiknya berupa `Dialog`/`AlertDialog`.
  dialog,

  /// Lewat `showModalBottomSheet` (scroll-controlled, dengan drag handle).
  bottomSheet,

  /// Tanpa dialog atau modal penjelasan apapun. Langsung meminta izin
  /// Kontak sistem jika belum diberikan.
  none,
}

/// UI penjelasan milik app consumer yang ditampilkan sebelum dialog izin
/// sistem. Bebas berupa dialog, bottom sheet, atau halaman.
///
/// Return `true` untuk lanjut ke dialog izin sistem. `false` atau `null`
/// (misalnya ditutup dengan swipe atau tap di luar) membatalkan, dan
/// [WaPermissionGate.ensureReady] mengembalikan `false`.
typedef WaPermissionDialogBuilder =
    Future<bool?> Function(
      BuildContext context,
      WaPermissionRationale rationale,
    );

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
  ///
  /// Dialog bawaan bisa diganti UI milik app consumer dengan salah satu dari:
  ///
  /// * [customWidget]: cukup kirim widget-nya; library menampilkannya sesuai
  ///   [presentation]. Widget menutup dirinya sendiri dengan
  ///   `Navigator.of(context).pop(true)` untuk lanjut ke dialog izin sistem,
  ///   atau `pop(false)` untuk batal.
  /// * [customDialog]: kontrol penuh atas cara menampilkan (route, animasi,
  ///   halaman penuh, dll). Return `true` untuk lanjut.
  ///
  /// Keduanya hanya ditampilkan jika izin belum granted. Untuk review Play
  /// Store, UI tersebut tetap harus menjelaskan data apa yang diakses dan
  /// untuk apa; gunakan [WaPermissionRationale.defaultDisclosure].
  ///
  /// ```dart
  /// await WaPermissionGate.ensureReady(
  ///   context,
  ///   appName: 'QRISKu',
  ///   purpose: 'memverifikasi nomor WA milikmu',
  ///   customWidget: const MyRationaleSheet(),
  ///   presentation: WaPermissionPresentation.bottomSheet,
  /// );
  /// ```
  static Future<bool> ensureReady(
    BuildContext context, {
    String? appName,
    String? purpose,
    Widget? customWidget,
    WaPermissionPresentation presentation = WaPermissionPresentation.dialog,
    WaPermissionDialogBuilder? customDialog,
  }) async {
    assert(
      customWidget == null || customDialog == null,
      'Pakai customWidget atau customDialog, jangan keduanya.',
    );
    assert(
      presentation == WaPermissionPresentation.none ||
          customWidget != null ||
          customDialog != null ||
          (appName != null && purpose != null),
      'appName dan purpose dibutuhkan bila menampilkan dialog bawaan.',
    );
    if (await Permission.contacts.isGranted) return true;
    if (!context.mounted) return false;

    if (presentation == WaPermissionPresentation.none) {
      final res = await Permission.contacts.request();
      return res.isGranted;
    }

    final rationale = WaPermissionRationale(
      appName: appName ?? '',
      purpose: purpose ?? '',
    );
    final show =
        customDialog ??
        (customWidget != null
            ? (BuildContext c, WaPermissionRationale _) =>
                  _showWidget(c, customWidget, presentation)
            : _showDefaultDialog);

    final proceed = await show(context, rationale);
    if (proceed != true) return false;
    final res = await Permission.contacts.request();
    return res.isGranted;
  }

  static Future<bool?> _showWidget(
    BuildContext context,
    Widget widget,
    WaPermissionPresentation presentation,
  ) {
    return switch (presentation) {
      WaPermissionPresentation.dialog => showDialog<bool>(
        context: context,
        builder: (_) => widget,
      ),
      WaPermissionPresentation.bottomSheet => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => SafeArea(child: widget),
      ),
      WaPermissionPresentation.none => Future.value(null),
    };
  }

  static Future<bool?> _showDefaultDialog(
    BuildContext context,
    WaPermissionRationale rationale,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(rationale.title),
        content: Text('${rationale.message}\n\n${rationale.disclosure}'),
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
  }

  /// Izin notifikasi (Android 13+) untuk notifikasi "kembali ke app"
  /// setelah WA dibuka lewat `confirmOpenWhatsApp`. Opsional: tanpa izin
  /// ini pengecekan tetap jalan, user hanya perlu kembali sendiri.
  static Future<bool> ensureNotifications() async {
    final res = await Permission.notification.request();
    return res.isGranted;
  }
}
