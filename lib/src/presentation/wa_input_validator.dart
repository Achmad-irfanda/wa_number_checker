import 'dart:async';

import '../data/phone_normalizer.dart';
import '../domain/wa_check_result.dart';
import '../wa_number_checker.dart';

/// Helper form (`onChanged`-aman) di atas [WaNumberChecker].
///
/// ```dart
/// validator = WaInputValidator(
///   checker: checker,
///   onResult: (r) => setState(() => result = r),
/// );
/// TextField(onChanged: validator.onChanged, ...)
/// ```
///
/// Menjamin: distinct + plausible-gate + debounce + cache per nomor +
/// cancel watch sebelumnya. Tombol submit TIDAK perlu diblokir —
/// hasil telat hanya jadi warning.
class WaInputValidator {
  WaInputValidator({
    required WaNumberChecker checker,
    required void Function(WaCheckResult result) onResult,
    this.debounce = const Duration(milliseconds: 800),
  }) : _checker = checker,
       _onResult = onResult;

  final WaNumberChecker _checker;
  final void Function(WaCheckResult) _onResult;

  /// Jeda setelah ketikan terakhir sebelum hit library.
  final Duration debounce;

  final Map<String, WaCheckResult> _cache = {};
  String _lastNormalized = '';
  Timer? _timer;
  bool _disposed = false;

  /// Panggil dari `onChanged`. Aman dipanggil tiap keystroke.
  void onChanged(String raw) {
    if (_disposed) return;
    final normalized = normalizeWaPhone(raw.trim());
    if (normalized == _lastNormalized) return; // distinct
    _lastNormalized = normalized;
    _timer?.cancel();
    if (!isPlausibleWaPhone(normalized)) return; // prefix → netral
    if (_cache.containsKey(normalized)) {
      _onResult(_cache[normalized]!);
      return;
    }
    _timer = Timer(debounce, () async {
      if (_disposed) return;
      await _checker.cancel(); // bunuh watch lama (anti pile-up)
      final r = await _checker.verify(normalized);
      if (_disposed) return;
      // jangan timpa hasil nomor yang lebih baru
      if (_lastNormalized != normalized) return;
      _cache[normalized] = r;
      _onResult(r);
    });
  }

  /// Bersihkan cache (mis. ganti sesi registrasi).
  void clearCache() => _cache.clear();

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _checker.cancel();
  }
}
