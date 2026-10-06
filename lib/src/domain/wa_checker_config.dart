/// Konfigurasi global [WaNumberChecker].
///
/// Semua nilai bisa di-override per panggilan (`verify(..., timeout: ...)`
/// / `checkWithInsert(..., cleanup: ...)`).
class WaCheckerConfig {
  const WaCheckerConfig({
    this.timeout = const Duration(seconds: 15),
    this.autoCleanup = false,
    this.maxStoredContacts = 100,
    this.minInsertInterval = const Duration(seconds: 10),
    this.contactTag = 'WA_CHECK',
    this.openWhatsAppTimeout = const Duration(seconds: 15),
    this.progressNoticeTitle = 'Memverifikasi nomor WhatsApp…',
    this.progressNoticeBody = 'Mohon tunggu sebentar',
    this.returnNoticeTitle = 'Verifikasi selesai',
    this.returnNoticeBody = 'Ketuk untuk kembali ke aplikasi',
    this.notRegisteredNoticeTitle = 'Nomor WhatsApp tidak valid',
    this.notRegisteredNoticeBody =
        'Nomor tidak terdaftar di WhatsApp. Ketuk untuk kembali ke aplikasi',
  });

  /// Timeout tunggu sync per pengecekan insert.
  final Duration timeout;

  /// Hapus kontak sementara begitu pengecekan selesai. Default `false`:
  /// kontak disimpan sebagai cache supaya cek ulang nomor yang sama tidak
  /// perlu membuka WA lagi (lihat [maxStoredContacts]).
  final bool autoCleanup;

  /// Batas jumlah nomor berbeda yang disimpan di akun temp. Saat tercapai,
  /// seluruh isinya dibuang sebelum insert berikutnya.
  final int maxStoredContacts;

  /// Jeda minimum antar insert (anti enumerasi massal + hemat resource).
  final Duration minInsertInterval;

  /// Prefix nama kontak sementara (mudah dikenali bila tertahan).
  final String contactTag;

  /// Timeout saat WA dibuka untuk verifikasi (`confirmOpenWhatsApp`).
  /// Lebih panjang dari [timeout]: WA yang mati butuh ~10 detik. Bila habis
  /// padahal WA sudah terbuka, hasilnya `notRegistered` (bukan `pending`).
  final Duration openWhatsAppTimeout;

  /// Judul notifikasi progress selama menunggu WA.
  final String progressNoticeTitle;

  /// Isi notifikasi progress selama menunggu WA.
  final String progressNoticeBody;

  /// Judul notifikasi "kembali ke app" setelah WA dibuka.
  final String returnNoticeTitle;

  /// Isi notifikasi "kembali ke app" setelah WA dibuka.
  final String returnNoticeBody;

  /// Judul notifikasi saat nomor tidak terdeteksi walau WA sudah dibuka.
  final String notRegisteredNoticeTitle;

  /// Isi notifikasi saat nomor tidak terdeteksi walau WA sudah dibuka.
  final String notRegisteredNoticeBody;
}
