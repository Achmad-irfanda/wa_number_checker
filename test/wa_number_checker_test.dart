import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wa_number_checker/wa_number_checker.dart';

void main() {
  group('normalizeWaPhone', () {
    test('08xx -> 62xx', () {
      expect(normalizeForTest('082230560490'), '6282230560490');
    });

    test('+62 stays 62xx', () {
      expect(normalizeForTest('+6282230560490'), '6282230560490');
    });

    test('strips non-digits', () {
      expect(normalizeForTest('0822-3056 0490'), '6282230560490');
    });
  });

  group('plausibility gate', () {
    test('prefix ditolak', () {
      expect(isPlausibleForTest('08'), isFalse);
      expect(isPlausibleForTest('62822'), isFalse);
    });

    test('full number diterima', () {
      expect(isPlausibleForTest('6282230560490'), isTrue);
    });
  });

  group('WaCheckStatus', () {
    test('hanya registered yang isValid', () {
      for (final s in WaCheckStatus.values) {
        final r = WaCheckResult(status: s, normalized: '62822');
        expect(r.isValid, s == WaCheckStatus.registered, reason: '$s');
      }
    });

    test('pending/offline/storageBlocked itu uncertain (netral)', () {
      expect(WaCheckStatus.pending.isUncertain, isTrue);
      expect(WaCheckStatus.offline.isUncertain, isTrue);
      expect(WaCheckStatus.storageBlocked.isUncertain, isTrue);
      expect(WaCheckStatus.notRegistered.isUncertain, isFalse);
      expect(WaCheckStatus.registered.isUncertain, isFalse);
    });
  });

  group('WaCheckerConfig', () {
    test('default: kontak disimpan (maks 100), timeout 15s', () {
      const c = WaCheckerConfig();
      expect(c.autoCleanup, isFalse);
      expect(c.maxStoredContacts, 100);
      expect(c.timeout, const Duration(seconds: 15));
    });
  });

  group('WaCheckResult', () {
    test('detectedBy bisa keduanya', () {
      const r = WaCheckResult(
        status: WaCheckStatus.registered,
        normalized: '62822',
        detectedBy: {WaApp.whatsapp, WaApp.whatsappBusiness},
      );
      expect(r.isValid, isTrue);
      expect(r.detectedBy, hasLength(2));
    });
  });

  group('platform selain Android', () {
    // Tanpa mock channel: kalau guard bocor, panggilan ini melempar
    // MissingPluginException.
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      test('$platform -> unsupported tanpa menyentuh channel', () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final checker = WaNumberChecker();

        expect((await checker.getDeviceInfo()).unsupported, isTrue);
        for (final r in [
          await checker.verify('08221234567'),
          await checker.checkExisting('08221234567'),
          await checker.checkWithInsert('08221234567'),
        ]) {
          expect(r.status, WaCheckStatus.unsupported);
          expect(r.normalized, '628221234567');
        }
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });
}

// Diuji lewat API publik (re-export dari barrel) agar refactor
// internal tidak merusak kontrak consumer.
String normalizeForTest(String raw) => normalizeWaPhone(raw);
bool isPlausibleForTest(String n) => isPlausibleWaPhone(n);
