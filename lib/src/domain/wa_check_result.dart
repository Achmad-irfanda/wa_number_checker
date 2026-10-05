import 'wa_app.dart';
import 'wa_check_status.dart';

/// Hasil satu kali pengecekan nomor.
///
/// [isValid] true hanya saat [status] == [WaCheckStatus.registered],
/// sehingga consumer simpel cukup pakai satu flag. Consumer advance
/// bisa membedakan negatif ([WaCheckStatus.notRegistered]) dari
/// netral ([WaCheckStatus.isUncertain]) lewat [status].
class WaCheckResult {
  const WaCheckResult({
    required this.status,
    required this.normalized,
    this.detectedBy = const {},
    this.installedApps = const {},
    this.activeApps = const {},
    this.hints = const {},
    this.latencyMs,
  });

  /// Status penuh.
  final WaCheckStatus status;

  /// Nomor ternormalisasi (`08xx`/`+62`/`62` → `62xx`).
  final String normalized;

  /// App mana yang mendeteksi nomor (bisa keduanya).
  final Set<WaApp> detectedBy;

  /// App yang terinstal di device.
  final Set<WaApp> installedApps;

  /// App yang aktif (login / pernah sync).
  final Set<WaApp> activeApps;

  /// Petunjuk tambahan, mis. `powerSaveActive`, `timeoutAfterMs=15000`.
  final Set<String> hints;

  /// Jeda insert → registered dalam ms (jika sempat insert).
  final int? latencyMs;

  /// True hanya saat terdaftar. Alias nyaman untuk consumer simpel.
  bool get isValid => status.isRegistered;

  @override
  String toString() =>
      'WaCheckResult(status: $status, normalized: $normalized, '
      'detectedBy: $detectedBy, hints: $hints, latencyMs: $latencyMs)';
}
