import 'wa_app.dart';

/// Kondisi WA di device. Lihat [WaNumberChecker.getDeviceInfo].
class WaDeviceInfo {
  const WaDeviceInfo({
    required this.installedApps,
    required this.activeApps,
    required this.online,
    required this.powerSave,
    required this.tempAccountReady,
    this.unsupported = false,
  });

  final Set<WaApp> installedApps;
  final Set<WaApp> activeApps;
  final bool online;
  final bool powerSave;
  final bool tempAccountReady;

  /// True di iOS (library Android-only).
  final bool unsupported;

  bool get hasAnyInstalled => installedApps.isNotEmpty;
  bool get hasAnyActive => activeApps.isNotEmpty;
}
