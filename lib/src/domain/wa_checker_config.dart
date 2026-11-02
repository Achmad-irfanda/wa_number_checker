/// Gaya tampilan notifikasi heads-up saat WhatsApp dibuka.
enum WaNoticeStyle {
  /// Pendekatan A: Standard Rich Notification bawaan Android.
  /// Menggunakan BigTextStyle, timer/chronometer sistem, progress bar,
  /// dan tombol action [Kembali ke Aplikasi].
  standard,

  /// Pendekatan B: Custom Layout (RemoteViews).
  /// Menggunakan layout XML khusus yang lebih luas dengan timer,
  /// teks proses multi-baris, progress bar, dan tombol custom [Kembali ke Aplikasi].
  custom,
}

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
    this.openWhatsAppTimeout = const Duration(seconds: 8),
    this.noticeStyle = WaNoticeStyle.standard,
    this.returnActionText = 'Kembali ke aplikasi',
    this.autoReturn = true,
    this.autoReturnDelay = const Duration(milliseconds: 4500),
    this.progressNoticeTitle = 'Memverifikasi nomor WhatsApp…',
    this.progressNoticeBody = 'Mohon tunggu sebentar',
    this.returnNoticeTitle = 'Nomor WhatsApp terdaftar',
    this.returnNoticeBody = 'Ketuk untuk kembali ke aplikasi',
    this.pendingNoticeTitle = 'Nomor WhatsApp belum bisa dipastikan',
    this.pendingNoticeBody = 'Ketuk untuk kembali ke aplikasi',
    this.notRegisteredNoticeTitle = 'Nomor WhatsApp tidak valid',
    this.notRegisteredNoticeBody =
        'Nomor tidak terdaftar di WhatsApp. Ketuk untuk kembali ke aplikasi',
  });

  /// Gaya tampilan notifikasi: [WaNoticeStyle.standard] (Pendekatan A)
  /// atau [WaNoticeStyle.custom] (Pendekatan B).
  final WaNoticeStyle noticeStyle;

  /// Teks tombol aksi pada notifikasi untuk kembali ke aplikasi client.
  final String returnActionText;

  /// Coba bawa user kembali ke aplikasi client bila tombol di notifikasi
  /// hasil belum ditekan setelah [autoReturnDelay]. Android bisa memblokir
  /// ini saat app di background; notifikasi hasil tetap ada sebagai jalan
  /// kembali. Default: `true`.
  final bool autoReturn;

  /// Jeda antara notifikasi hasil dan percobaan [autoReturn].
  final Duration autoReturnDelay;

  /// Timeout tunggu sync per pengecekan insert.
  final Duration timeout;

  /// Hapus kontak sementara begitu pengecekan selesai. Default `false`:
  /// kontak disimpan sebagai cache supaya cek ulang nomor yang sama tidak
  /// perlu membuka WA lagi (lihat [maxStoredContacts]).
  final bool autoCleanup;

  /// Batas jumlah nomor berbeda yang disimpan di akun temp. Saat tercapai,
  /// seluruh isinya dibuang sebelum insert berikutnya.
  final int maxStoredContacts;

  /// Jeda minimum antar insert nomor berbeda (anti enumerasi massal + hemat
  /// resource). Mengulang nomor yang sama tidak dibatasi.
  final Duration minInsertInterval;

  /// Prefix nama kontak sementara (mudah dikenali bila tertahan).
  final String contactTag;

  /// Batas tunggu saat WA dibuka untuk verifikasi (`confirmOpenWhatsApp`).
  /// Bila habis hasilnya `pending`: WA yang start dari mati butuh ~10 detik,
  /// jadi nomor yang belum muncul belum tentu tidak terdaftar.
  final Duration openWhatsAppTimeout;

  /// Judul notifikasi progress selama menunggu WA.
  final String progressNoticeTitle;

  /// Isi notifikasi progress selama menunggu WA.
  final String progressNoticeBody;

  /// Judul notifikasi saat nomor terdeteksi terdaftar.
  final String returnNoticeTitle;

  /// Isi notifikasi saat nomor terdeteksi terdaftar.
  final String returnNoticeBody;

  /// Judul notifikasi saat nomor belum muncul sampai [openWhatsAppTimeout].
  final String pendingNoticeTitle;

  /// Isi notifikasi saat nomor belum muncul sampai [openWhatsAppTimeout].
  final String pendingNoticeBody;

  @Deprecated(
    'Tidak dipakai lagi: timeout kini `pending`. Pakai pendingNoticeTitle.',
  )
  final String notRegisteredNoticeTitle;

  @Deprecated(
    'Tidak dipakai lagi: timeout kini `pending`. Pakai pendingNoticeBody.',
  )
  final String notRegisteredNoticeBody;
}
