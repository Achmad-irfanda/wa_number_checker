/// Konfigurasi global [WaNumberChecker].
///
/// Semua nilai bisa di-override per panggilan (`verify(..., timeout: ...)`
/// / `checkWithInsert(..., cleanup: ...)`).
class WaCheckerConfig {
  const WaCheckerConfig({
    this.timeout = const Duration(seconds: 15),
    this.autoCleanup = true,
    this.minInsertInterval = const Duration(seconds: 10),
    this.contactTag = 'WA_CHECK',
  });

  /// Timeout tunggu sync per pengecekan insert.
  final Duration timeout;

  /// Default hapus kontak sementara setelah selesai.
  /// Aman by default: kontak temp tidak ikut terhapus saat uninstall.
  final bool autoCleanup;

  /// Jeda minimum antar insert (anti enumerasi massal + hemat resource).
  final Duration minInsertInterval;

  /// Prefix nama kontak sementara (mudah dikenali bila tertahan).
  final String contactTag;
}
