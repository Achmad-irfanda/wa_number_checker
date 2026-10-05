import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'data/native_bridge.dart';
import 'data/phone_normalizer.dart';
import 'domain/wa_check_result.dart';
import 'domain/wa_check_status.dart';
import 'domain/wa_checker_config.dart';
import 'domain/wa_device_info.dart';

/// Entry point umum `wa_number_checker`.
///
/// ```dart
/// final checker = WaNumberChecker(
///   config: const WaCheckerConfig(timeout: Duration(seconds: 15)),
/// );
/// final r = await checker.verify('0822...');
/// if (r.isValid) { ... } // registered
/// ```
///
/// Android-only (sync WA/WA Business via Contacts Provider + akun temp
/// `com.wa_checker.temp`). iOS selalu [WaCheckStatus.unsupported].
/// Library tidak meminta izin sendiri — pakai
/// [WaPermissionGate.ensureReady] (butuh `appName` app consumer) atau
/// minta izin dengan UX milikmu, lalu panggil [verify].
class WaNumberChecker {
  WaNumberChecker({this.config = const WaCheckerConfig(), NativeBridge? bridge})
    : _bridge = bridge ?? NativeBridge();

  final WaCheckerConfig config;
  final NativeBridge _bridge;

  int _generation = 0;
  int? _lastContactId;
  DateTime? _lastInsertAt;
  bool _disposed = false;
  StreamSubscription? _observerSub;

  /// Lapis simpel (80% consumer): check-then-insert otomatis.
  Future<WaCheckResult> verify(
    String phone, {
    Duration? timeout,
    bool? cleanup,
  }) async {
    final myGen = ++_generation;
    final normalized = normalizeWaPhone(phone);
    final clean = cleanup ?? config.autoCleanup;

    bool cancelled() => myGen != _generation || _disposed;

    // 0. Izin (library tidak request sendiri).
    if (!await Permission.contacts.isGranted) {
      return WaCheckResult(
        status: WaCheckStatus.permissionDenied,
        normalized: normalized,
      );
    }

    // 1. Pre-check fail-fast.
    final info = await getDeviceInfo();
    if (info.unsupported) {
      return WaCheckResult(
        status: WaCheckStatus.unsupported,
        normalized: normalized,
      );
    }
    if (!info.hasAnyInstalled) {
      return WaCheckResult(
        status: WaCheckStatus.waNotInstalled,
        normalized: normalized,
      );
    }
    if (!info.hasAnyActive) {
      return WaCheckResult(
        status: WaCheckStatus.waNotActive,
        normalized: normalized,
        installedApps: info.installedApps,
      );
    }
    if (!info.online) {
      return WaCheckResult(
        status: WaCheckStatus.offline,
        normalized: normalized,
        installedApps: info.installedApps,
        activeApps: info.activeApps,
      );
    }

    // 2. Fast-path read-only (murah, works di power-save).
    final existing = await checkExisting(phone);
    if (existing.status == WaCheckStatus.registered || cancelled()) {
      return existing.status == WaCheckStatus.registered
          ? existing
          : const WaCheckResult(
              status: WaCheckStatus.cancelled,
              normalized: '',
            ).copyNormalized(normalized);
    }

    // 3. Rate-limit insert (anti enumerasi + hemat resource).
    final now = DateTime.now();
    if (_lastInsertAt != null &&
        now.difference(_lastInsertAt!) < config.minInsertInterval) {
      return WaCheckResult(
        status: WaCheckStatus.pending,
        normalized: normalized,
        installedApps: info.installedApps,
        activeApps: info.activeApps,
        hints: {'rateLimited'},
      );
    }

    // 4. Insert + watch.
    return checkWithInsert(
      phone,
      timeout: timeout,
      cleanup: clean,
      generation: myGen,
      preloadedInfo: info,
    );
  }

  /// Read-only: nomor sudah ada + punya raw contact WA?
  Future<WaCheckResult> checkExisting(String phone) async {
    final normalized = normalizeWaPhone(phone);
    if (!await Permission.contacts.isGranted) {
      return WaCheckResult(
        status: WaCheckStatus.permissionDenied,
        normalized: normalized,
      );
    }
    try {
      final r = await _bridge.checkExisting(phone);
      final info = await getDeviceInfo();
      if (r.found) {
        return WaCheckResult(
          status: WaCheckStatus.registered,
          normalized: normalized,
          detectedBy: r.detectedBy,
          installedApps: info.installedApps,
          activeApps: info.activeApps,
          hints: info.powerSave ? const {'powerSaveActive'} : const {},
        );
      }
      if (info.unsupported) {
        return WaCheckResult(
          status: WaCheckStatus.unsupported,
          normalized: normalized,
        );
      }
      if (!info.hasAnyInstalled) {
        return WaCheckResult(
          status: WaCheckStatus.waNotInstalled,
          normalized: normalized,
        );
      }
      if (!info.hasAnyActive) {
        return WaCheckResult(
          status: WaCheckStatus.waNotActive,
          normalized: normalized,
          installedApps: info.installedApps,
        );
      }
      if (!info.online) {
        return WaCheckResult(
          status: WaCheckStatus.offline,
          normalized: normalized,
          installedApps: info.installedApps,
          activeApps: info.activeApps,
        );
      }
      return WaCheckResult(
        status: WaCheckStatus.notRegistered,
        normalized: normalized,
        installedApps: info.installedApps,
        activeApps: info.activeApps,
        hints: info.powerSave ? const {'powerSaveActive'} : const {},
      );
    } on PlatformException catch (e) {
      if (e.code == 'UNSUPPORTED') {
        return WaCheckResult(
          status: WaCheckStatus.unsupported,
          normalized: normalized,
        );
      }
      rethrow;
    }
  }

  /// Advance: insert kontak sementara di akun temp + watch sync.
  /// [cancel] otomatis dipanggil untuk watch sebelumnya.
  Future<WaCheckResult> checkWithInsert(
    String phone, {
    Duration? timeout,
    bool? cleanup,
    int? generation,
    WaDeviceInfo? preloadedInfo,
  }) async {
    final myGen = generation ?? ++_generation;
    final normalized = normalizeWaPhone(phone);
    final limit = timeout ?? config.timeout;
    final clean = cleanup ?? config.autoCleanup;
    bool cancelled() => myGen != _generation || _disposed;

    if (!await Permission.contacts.isGranted) {
      return WaCheckResult(
        status: WaCheckStatus.permissionDenied,
        normalized: normalized,
      );
    }
    final info = preloadedInfo ?? await getDeviceInfo();
    final hints = <String>{
      if (info.powerSave) 'powerSaveActive',
      'timeoutAfterMs=${limit.inMilliseconds}',
    };

    final t0 = DateTime.now().millisecondsSinceEpoch;
    int? contactId;
    try {
      await _bridge.startObserver();
      final ins = await _bridge.insertTemp(phone, config.contactTag);
      contactId = ins.contactId;
      _lastContactId = contactId;
      _lastInsertAt = DateTime.now();
    } catch (_) {
      await _bridge.stopObserver();
      // Mis. ROM menolak write (kebijakan akun default).
      return WaCheckResult(
        status: WaCheckStatus.storageBlocked,
        normalized: normalized,
        installedApps: info.installedApps,
        activeApps: info.activeApps,
        hints: {...hints, 'insertRejected'},
      );
    }
    if (cancelled()) {
      await _finishWatch(contactId: contactId, cleanup: true);
      return WaCheckResult(
        status: WaCheckStatus.cancelled,
        normalized: normalized,
      );
    }

    final completer = Completer<WaCheckResult>();
    Timer? timer;

    Future<void> finish(WaCheckResult r) async {
      if (completer.isCompleted) return;
      timer?.cancel();
      await _finishWatch(
        contactId: contactId,
        cleanup: clean && r.status != WaCheckStatus.cancelled,
      );
      if (r.status == WaCheckStatus.registered) _lastContactId = null;
      completer.complete(r);
    }

    Future<void> poll({bool silent = true}) async {
      if (completer.isCompleted || cancelled()) return;
      try {
        final r = await _bridge.checkExisting(phone);
        if (cancelled()) {
          await finish(
            WaCheckResult(
              status: WaCheckStatus.cancelled,
              normalized: normalized,
            ),
          );
          return;
        }
        if (r.found) {
          final dt = DateTime.now().millisecondsSinceEpoch - t0;
          await finish(
            WaCheckResult(
              status: WaCheckStatus.registered,
              normalized: normalized,
              detectedBy: r.detectedBy,
              installedApps: info.installedApps,
              activeApps: info.activeApps,
              hints: hints,
              latencyMs: dt,
            ),
          );
        } else if (!silent) {
          // observer fire tanpa hasil — tunggu event berikutnya
        }
      } catch (_) {}
    }

    await _observerSub?.cancel();
    _observerSub = _bridge.contactEvents().listen(
      (_) => poll(),
      onError: (_) {},
    );
    await poll();
    timer = Timer(limit, () async {
      // Timeout bukan vonis negatif: bedakan pending dari notRegistered.
      // Sinyal tidak langsung (observer fire tapi target tak muncul)
      // butuh tracking sync per-app — v0.1.0 konservatif → pending.
      await finish(
        WaCheckResult(
          status: WaCheckStatus.pending,
          normalized: normalized,
          installedApps: info.installedApps,
          activeApps: info.activeApps,
          hints: hints,
        ),
      );
    });

    final out = await completer.future;
    if (cancelled() && out.status != WaCheckStatus.registered) {
      return WaCheckResult(
        status: WaCheckStatus.cancelled,
        normalized: normalized,
      );
    }
    return out;
  }

  Future<WaDeviceInfo> getDeviceInfo() => _bridge.getDeviceInfo();

  /// Batalkan watch yang sedang berjalan + bersihkan sisa kontak temp.
  Future<void> cancel() async {
    _generation++;
    final id = _lastContactId;
    _lastContactId = null;
    await _finishWatch(contactId: id, cleanup: true);
  }

  Future<void> _finishWatch({int? contactId, required bool cleanup}) async {
    try {
      await _observerSub?.cancel();
    } catch (_) {}
    _observerSub = null;
    await _bridge.stopObserver();
    if (cleanup && contactId != null && contactId > 0) {
      await _bridge.deleteContact(contactId);
      if (_lastContactId == contactId) _lastContactId = null;
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _observerSub?.cancel();
    _bridge.stopObserver();
  }
}

extension on WaCheckResult {
  WaCheckResult copyNormalized(String normalized) => WaCheckResult(
    status: status,
    normalized: normalized,
    detectedBy: detectedBy,
    installedApps: installedApps,
    activeApps: activeApps,
    hints: hints,
    latencyMs: latencyMs,
  );
}
