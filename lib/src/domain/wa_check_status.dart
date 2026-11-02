/// Status hasil pengecekan nomor WhatsApp.
///
/// `registered` berarti nomor terdeteksi oleh minimal satu app
/// (WA biasa dan/atau WA Business). Semua nilai selain itu berarti
/// **tidak terbukti terdaftar** — `notRegistered` hanya berarti belum
/// dikenal device, `uncertain` (pending/offline/dsb) netral.
enum WaCheckStatus {
  /// Nomor terdaftar (via WA dan/atau WA Business).
  registered,

  /// Hasil `checkExisting()`: nomor belum dikenal WA di device ini. WA belum
  /// tentu sudah mengeceknya; `verify()` tidak mengembalikan status ini.
  notRegistered,

  /// Timeout tanpa kesimpulan, dengan atau tanpa WA dibuka (hint `waOpened`).
  /// Netral, boleh retry.
  pending,

  /// Tidak ada internet saat pengecekan. Pengecekan tidak dijalankan.
  offline,

  /// WA dan WA Business sama-sama tidak terinstal.
  waNotInstalled,

  /// Terinstal tapi tidak ada yang login / pernah sync.
  waNotActive,

  /// Izin kontak belum diberikan.
  permissionDenied,

  /// Platform tidak didukung (selain Android).
  unsupported,

  /// Insert ke provider ditolak (mis. kebijakan ROM). Netral.
  storageBlocked,

  /// Pengecekan dibatalkan via [WaNumberChecker.cancel].
  cancelled,
}

/// True hanya untuk [WaCheckStatus.registered].
extension WaCheckStatusX on WaCheckStatus {
  bool get isRegistered => this == WaCheckStatus.registered;

  /// True untuk status netral yang layak retry
  /// ([pending], [offline], [storageBlocked]).
  bool get isUncertain => switch (this) {
    WaCheckStatus.pending ||
    WaCheckStatus.offline ||
    WaCheckStatus.storageBlocked => true,
    _ => false,
  };
}
