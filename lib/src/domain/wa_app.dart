/// App WhatsApp mana yang mendeteksi nomor.
enum WaApp {
  /// WhatsApp reguler (`com.whatsapp`).
  whatsapp,

  /// WhatsApp Business (`com.whatsapp.w4b`).
  whatsappBusiness,
}

/// Parsing dari string native (`whatsapp` / `whatsappBusiness`).
WaApp? waAppFromString(String s) => switch (s) {
  'whatsapp' => WaApp.whatsapp,
  'whatsappBusiness' => WaApp.whatsappBusiness,
  _ => null,
};
