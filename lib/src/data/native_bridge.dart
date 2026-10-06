import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/wa_app.dart';
import '../domain/wa_device_info.dart';

/// Primitif channel ke native. Orkestrasi ada di [WaNumberChecker].
class NativeBridge {
  NativeBridge({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel('wa_number_checker/methods'),
      _events = events ?? const EventChannel('wa_number_checker/events');

  final MethodChannel _methods;
  final EventChannel _events;

  @visibleForTesting
  MethodChannel get debugMethods => _methods;

  Future<String> normalize(String phone) async =>
      (await _methods.invokeMethod<String>('normalize', {'phone': phone})) ??
      phone;

  Future<WaDeviceInfo> getDeviceInfo() async {
    final m = await _methods.invokeMapMethod<String, dynamic>('getDeviceInfo');
    Set<WaApp> apps(String key, {required bool flag}) {
      final out = <WaApp>{};
      if (m?[key] == true) {
        out.add(flag ? WaApp.whatsapp : WaApp.whatsappBusiness);
      }
      return out;
    }

    if (m?['unsupported'] == true) {
      return const WaDeviceInfo(
        installedApps: {},
        activeApps: {},
        online: false,
        powerSave: false,
        tempAccountReady: false,
        unsupported: true,
      );
    }
    return WaDeviceInfo(
      installedApps: {
        ...apps('waInstalled', flag: true),
        ...apps('w4bInstalled', flag: false),
      },
      activeApps: {
        ...apps('waActive', flag: true),
        ...apps('w4bActive', flag: false),
      },
      online: m?['online'] == true,
      powerSave: m?['powerSave'] == true,
      tempAccountReady: m?['tempAccountReady'] != false,
    );
  }

  Future<({bool found, Set<WaApp> detectedBy, int? contactId})> checkExisting(
    String phone,
  ) async {
    final m = await _methods
        .invokeMapMethod<String, dynamic>('checkExisting', {'phone': phone})
        .catchError((Object e) {
          if (e is PlatformException && e.code == 'UNSUPPORTED') {
            return <String, dynamic>{'found': false, 'detectedBy': []};
          }
          throw e;
        });
    final by = <WaApp>{};
    for (final s in (m?['detectedBy'] as List? ?? [])) {
      final a = waAppFromString('$s');
      if (a != null) by.add(a);
    }
    final cid = (m?['contactId'] as num?)?.toInt();
    return (found: m?['found'] == true, detectedBy: by, contactId: cid);
  }

  Future<({int contactId, int rawContactId})> insertTemp(
    String phone,
    String tag,
    int maxStored,
  ) async {
    final m = await _methods.invokeMapMethod<String, dynamic>('insertTemp', {
      'phone': phone,
      'tag': tag,
      'maxStored': maxStored,
    });
    return (
      contactId: (m?['contactId'] as num? ?? -1).toInt(),
      rawContactId: (m?['rawContactId'] as num? ?? -1).toInt(),
    );
  }

  Future<void> deleteContact(int contactId) async {
    try {
      await _methods.invokeMethod('deleteContact', {'contactId': contactId});
    } catch (_) {
      // cleanup best-effort
    }
  }

  Future<void> startObserver() async {
    try {
      await _methods.invokeMethod('startObserver');
    } catch (_) {
      // iOS stub: tidak ada observer, re-query mengandalkan timeout saja
    }
  }

  Future<void> stopObserver() async {
    try {
      await _methods.invokeMethod('stopObserver');
    } catch (_) {}
  }

  /// Buka WA ke layar (pemicu WA mengecek kontak baru). False jika gagal.
  Future<bool> openWhatsApp() async {
    try {
      return await _methods.invokeMethod<bool>('openWhatsApp') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Notifikasi "ketuk untuk kembali". False jika notifikasi tidak diizinkan.
  Future<bool> showReturnNotice(String title, String body) async {
    try {
      return await _methods.invokeMethod<bool>('showReturnNotice', {
            'title': title,
            'body': body,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Notifikasi progress selama menunggu WA; bar terisi sampai [duration].
  Future<bool> showProgressNotice(
    String title,
    String body,
    Duration duration,
  ) async {
    try {
      return await _methods.invokeMethod<bool>('showProgressNotice', {
            'title': title,
            'body': body,
            'durationMs': duration.inMilliseconds,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelReturnNotice() async {
    try {
      await _methods.invokeMethod('cancelReturnNotice');
    } catch (_) {}
  }

  /// Event mentah observer contacts (tiap ada perubahan → re-query).
  Stream<Map> contactEvents() =>
      _events.receiveBroadcastStream().map((e) => Map.from(e as Map));
}
