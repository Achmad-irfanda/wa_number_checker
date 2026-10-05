# wa_number_checker

Check whether a phone number is registered on WhatsApp (and/or WhatsApp Business) via on-device contact sync. Built for registration forms: type a number, get a warning-level answer — never a blocker.

```dart
final checker = WaNumberChecker();

final ok = await WaPermissionGate.ensureReady(
  context,
  appName: 'MyApp', // your app's name, shown in the rationale dialog
  purpose: 'verfied your number WhatsApp for One Time Password',
);
if (!ok) return;

final r = await checker.verify('0822...');
if (r.isValid) {
  // registered — detectedBy tells which app: {whatsapp, whatsappBusiness}
} else if (r.status.isUncertain) {
  // pending / offline / storageBlocked — neutral, let the user continue
} else {
  // notRegistered / waNotInstalled / waNotActive —soft warning
}
```

Live form helper (debounce + cache + cancel, safe in `onChanged`):

```dart
validator = WaInputValidator(checker: checker, onResult: (r) {
  setState(() => result = r); // submit button stays enabled
});
TextField(onChanged: validator.onChanged);
```

## How it works

1. `checkExisting()` — read-only lookup via `PhoneLookup`, free even in power-save.
2. If missed, `checkWithInsert()` — inserts a temporary contact into a
   dedicated account (`com.wa_checker.temp`, never Google cloud), watches
   `RawContacts` with a `ContentObserver`, and reports `registered` with
   `detectedBy` once WA/WA Business sync picks the number up.
3. The temp contact is deleted afterwards (`autoCleanup: true` by default).

Number normalization (`08xx`/`+62`/`62` → `62xx`) is shared between Dart and
Kotlin. Inserts are rate-limited (1 per 10s) and always run off the UI thread.

## Honest limitations

- **Android-only.** iOS always returns `WaCheckStatus.unsupported`.
- **Sync-based, not real-time.** Expect ~seconds of delay; default timeout is
  15s. Treat the result as a hint for a warning label, not a security gate.
- **Timeout is neutral.** `pending` means "could not determine", not "invalid".
  Do not block registration on it — retry on submit / app resume.
- **Writes a temporary contact** to a dedicated on-device account and deletes
  it after the check (`autoCleanup`). No data leaves the device, nothing is
  sent to any server by this package.
- **Permissions merged into your app:** `READ_CONTACTS`, `WRITE_CONTACTS`,
  `ACCESS_NETWORK_STATE`, `GET_ACCOUNTS`, plus `<queries>` for
  `com.whatsapp` / `com.whatsapp.w4b`. You must show a prominent disclosure
  (see `WaPermissionGate.ensureReady`) and justify contacts access in Play
  Console, or your **app** update can be rejected. The package itself requests
  nothing silently.

## API layers

- Simple (most consumers): `verify()`, `WaInputValidator`, `WaPermissionGate`.
- Advanced: `checkExisting()`, `checkWithInsert()`, `cancel()`,
  `getDeviceInfo()`, `dispose()`.

See `example/` for a registration-form demo. Field-tested on Samsung/OneUI
with Google-default storage and power-save on.
