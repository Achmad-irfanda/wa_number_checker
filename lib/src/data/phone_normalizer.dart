/// Normalisasi Dart (mirror logika native, dipakai untuk gate di UI
/// tanpa round-trip channel): `08xx` → `62xx`, `+62` → `62`,
/// selain digit dibuang.
String normalizeWaPhone(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('08')) return '62${d.substring(1)}';
  return d;
}

/// True jika nomor layak dicek (bukan prefix ketikan).
bool isPlausibleWaPhone(String normalized) {
  if (normalized.length < 10) return false;
  return normalized.startsWith('62') || normalized.startsWith('08');
}
