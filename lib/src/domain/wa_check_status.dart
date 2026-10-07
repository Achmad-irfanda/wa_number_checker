/// Status hasil pengecekan nomor WhatsApp.
///
/// `registered` berarti nomor terdeteksi oleh minimal satu app
/// (WA biasa dan/atau WA Business). Semua nilai selain itu berarti
/// **tidak terbukti terdaftar** — bedakan `notRegistered` (negatif
/// terverifikasi) dari `uncertain` (pending/offline/dsb, netral).
enum WaCheckStatus {
  /// Nomor terdaftar (via WA dan/atau WA Business).
  registered,

  /// Ada WA aktif yang sync, nomor tidak muncul: negatif terverifikasi.
  notRegistered,

  /// Timeout tanpa kesimpulan (mis. sync tertunda). Netral, boleh retry.
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
