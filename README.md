# wa_number_checker

Check whether a phone number is registered on WhatsApp (and/or WhatsApp Business) via on-device contact sync. Built for registration forms: type a number, get a warning-level answer — never a blocker.

```dart
final checker = WaNumberChecker();

final ok = await WaPermissionGate.ensureReady(
  context,
  appName: 'MyApp', // your app's name, shown in the rationale dialog
  purpose: 'verify your WhatsApp number for one-time passwords',
);
if (!ok) return;

final r = await checker.verify(
  '0822...',
  // Called only when the number is not known on this device yet.
  // Return true to let the package open WhatsApp for the check.
  confirmOpenWhatsApp: () async {
    final agreed = await askUser('Open WhatsApp briefly to verify?');
    if (agreed) await WaPermissionGate.ensureNotifications();
    return agreed;
  },
);

if (r.isValid) {
  // registered — detectedBy tells which app: {whatsapp, whatsappBusiness}
} else if (r.status.isUncertain) {
  // pending / offline / storageBlocked — neutral, let the user continue
} else {
  // notRegistered / waNotInstalled / waNotActive — soft warning
}
```

## How it works

1. **Local lookup** (`checkExisting()`). Read-only. If WhatsApp has already
   marked the number in the device contacts, the result is `registered`
   immediately: nothing is inserted and WhatsApp is not opened. The number is
   matched through `PhoneLookup` and through the WhatsApp ID that WhatsApp
   stores on its own raw contacts.
2. **Insert and watch** (`checkWithInsert()`). Otherwise the number is stored
   as a contact in a dedicated account (`com.wa_checker.temp`, never Google
   cloud) and `RawContacts` is watched with a `ContentObserver`. The result is
   `registered` with `detectedBy` as soon as WhatsApp or WhatsApp Business
   marks the number.
3. **Open WhatsApp** (optional, see below). WhatsApp only looks up new
   contacts while it is on screen, so without this step a number that is new
   to the device usually ends as `pending`.

Number normalization (`08xx`/`+62`/`62` → `62xx`) is shared between Dart and
Kotlin. Inserts are rate-limited (1 per 10s) and always run off the UI thread.

## Opening WhatsApp

Pass `confirmOpenWhatsApp` to `verify()` to enable the full flow:

1. The callback runs only when step 1 found nothing. Show your own consent
   dialog there and return `true` to continue.
2. The package inserts the contact, opens WhatsApp and shows a **progress
   notification** ("verifying…") with a bar that fills up to the timeout.
3. As soon as the answer is known the notification turns into a **result
   notification**. Tapping it brings the user back to your app. `verify()`
   completes at the same moment, so the result is ready when they return.
4. If WhatsApp was open and the number did not show up within
   `openWhatsAppTimeout` (15s), the result is `notRegistered`.

Returning `false` from the callback (or not passing it) runs the check without
opening WhatsApp; a timeout then stays `pending`.

The notifications are posted by the package on behalf of your app, so they
carry your app's name and icon. They need the notification permission on
Android 13+: call `WaPermissionGate.ensureNotifications()` before the first
check. If it is denied the check still works, but nothing is shown and the
user has to switch back manually. If the user is already back in your app when
the result arrives, no notification is posted.

## Cached contacts

Checked numbers are kept in the dedicated account as a cache, so checking the
same registered number again finishes at step 1 without opening WhatsApp.
A number that is already stored is reused instead of inserted twice. When the
account holds `maxStoredContacts` numbers (default 100), it is emptied before
the next insert. Set `autoCleanup: true` to delete the contact right after
each check instead.

## Configuration

```dart
WaNumberChecker(
  config: const WaCheckerConfig(
    timeout: Duration(seconds: 15),             // without opening WhatsApp
    openWhatsAppTimeout: Duration(seconds: 15), // after WhatsApp was opened
    maxStoredContacts: 100,
    autoCleanup: false,
    minInsertInterval: Duration(seconds: 10),
    // Notification texts (defaults are in Indonesian).
    progressNoticeTitle: 'Verifying WhatsApp number…',
    progressNoticeBody: 'Please wait a moment',
    returnNoticeTitle: 'Verification finished',
    returnNoticeBody: 'Tap to return to the app',
    notRegisteredNoticeTitle: 'Not a WhatsApp number',
    notRegisteredNoticeBody: 'Tap to return to the app',
  ),
);
```

## Android Gradle Plugin 8

`permission_handler` 13.x requires Android Gradle Plugin 9. If your app still
builds with Android Gradle Plugin 8, the build fails in
`permission_handler_android` with `Unresolved reference: compilerOptions`.
Stay on 12.x by adding this to your app's `pubspec.yaml`:

```yaml
dependencies:
  permission_handler: ^12.0.3
```

## Honest limitations

- **Android-only.** iOS has no equivalent signal: WhatsApp does not write
  anything to the shared address book there. The package can still be a
  dependency of an iOS app; every check returns `WaCheckStatus.unsupported`.
- **WhatsApp must be on screen to detect a new number.** In the background it
  does not react to contact changes, and recent Android versions also cut its
  network access there. Numbers already known on the device are not affected.
- **Sync-based, not real-time.** With WhatsApp open, a registered number shows
  up in roughly 3–5 seconds, or about 10 seconds when WhatsApp starts cold.
  Treat the result as a hint for a warning label, not a security gate.
- **`notRegistered` after a timeout is an inference.** It means WhatsApp was
  open and did not mark the number in time. A slow device or network can turn
  a valid number into `notRegistered`, so offer a retry and do not block the
  user on it.
- **`pending` is neutral.** It means "could not determine", not "invalid".
- **Stores contacts on the device.** Checked numbers stay in a dedicated
  on-device account until the cache limit is reached or the app is
  uninstalled. They are hidden in the system Contacts app by default, but
  registered ones appear in the user's WhatsApp contact list under the name
  `WA_CHECK <digits>`. Nothing is sent to any server by this package.
- **Relies on WhatsApp internals.** Matching by WhatsApp ID reads the `SYNC1`
  column of WhatsApp's raw contacts, which is not a documented API and may
  change.
- **Permissions merged into your app:** `READ_CONTACTS`, `WRITE_CONTACTS`,
  `ACCESS_NETWORK_STATE`, `GET_ACCOUNTS`, `POST_NOTIFICATIONS`, plus
  `<queries>` for `com.whatsapp` / `com.whatsapp.w4b`. You must show a
  prominent disclosure (see `WaPermissionGate.ensureReady`) and justify
  contacts access in Play Console, or your **app** update can be rejected.
  The package itself requests nothing silently.

## API layers

- Simple (most consumers): `verify()`, `WaPermissionGate`.
- Advanced: `checkExisting()`, `checkWithInsert()`, `cancel()`,
  `getDeviceInfo()`, `dispose()`.
- `WaInputValidator` (debounce + cache for `onChanged`) is still available,
  but it inserts a contact for every plausible number typed and cannot open
  WhatsApp. A button that calls `verify()` is the recommended integration.

See `example/` for a commented demo of the full flow. Field-tested on
Samsung/One UI (Android 16) with Google-default storage.
