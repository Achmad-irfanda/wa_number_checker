## 0.2.1

* Widens `permission_handler` to `>=12.0.1 <14.0.0` (was `^11.3.1`).
* Apps that still build with Android Gradle Plugin 8 need
  `permission_handler: ^12.0.3` in their own `pubspec.yaml`:
  `permission_handler` 13.x requires Android Gradle Plugin 9. See the README.
* Removes the iOS stub and the `ios` platform declaration, so the package is
  listed as Android-only. It can still be a dependency of an app that also
  targets iOS.
* On every platform other than Android, checks return `unsupported` from Dart
  without touching the platform channel or the contacts permission. Before,
  iOS answered `permissionDenied` until contacts access was granted, and
  platforms without the stub threw `MissingPluginException`.


## 0.2.0

**Behavior changes**

* `autoCleanup` now defaults to `false`. Checked numbers are kept in the
  dedicated account as a cache (up to `maxStoredContacts`, default 100) so a
  repeated check of a registered number does not need WhatsApp again. Set
  `autoCleanup: true` to keep the old delete-after-check behavior.
* Adds the `POST_NOTIFICATIONS` permission to the consumer app's manifest.
* A timeout after WhatsApp was opened now returns `notRegistered` instead of
  `pending`.

**Added**

* `verify(confirmOpenWhatsApp: ...)` and `checkWithInsert(openWhatsApp: ...)`:
  open WhatsApp for the check, because WhatsApp only looks up new contacts
  while it is on screen.
* Progress notification while waiting and a result notification that brings
  the user back to the app when tapped.
* `WaPermissionGate.ensureNotifications()`.
* `WaCheckerConfig`: `openWhatsAppTimeout` (15s), `maxStoredContacts`,
  `progressNoticeTitle/Body`, `returnNoticeTitle/Body`,
  `notRegisteredNoticeTitle/Body`.
* Numbers are also matched by the WhatsApp ID stored on WhatsApp's own raw
  contacts, so a number WhatsApp already knows is found even when its entry
  is attached to a different contact.

**Fixed**

* `MissingPluginException`: Dart called `queryWa` while the native side
  handles `checkExisting`.
* Cleanup never deleted anything. It now removes only the raw contact in the
  dedicated account, so a user's own contact is never deleted with it.
* Only the first contact returned for a number was inspected; a registered
  number stored in several contacts could time out.
* A superseded check kept running until its own timeout and then switched off
  the observer of the newer check.
* Contacts were stored without a leading `+`, so short numbers such as
  `62811460943` were read as a local number and never detected.

**Example**

* Manual "Check and Verify" flow with the open-WhatsApp dialog; comments
  rewritten in English.

## 0.1.2

* update ui: example demo app library use for common user
* split `log` version stepper with divieder

## 0.1.1

* Fix dead relative link (`../wa_poc`) in README.

## 0.1.0

* Initial release.
* `verify()` (check-then-insert), `checkExisting()`, `checkWithInsert()`,
  `cancel()`, `getDeviceInfo()`, `dispose()`.
* Dedicated temp account `com.wa_checker.temp`: works with cloud-default
  storage (Samsung/OneUI) and power-save; never touches Google contacts.
* `WaCheckResult.isValid` + `WaCheckStatus` (registered / notRegistered /
  pending / offline / waNotInstalled / waNotActive / permissionDenied /
  unsupported / storageBlocked / cancelled).
* `WaPermissionGate.ensureReady(appName:..., purpose:...)` rationale helper
  and `WaInputValidator` debounce/cache/cancel helper for `onChanged` forms.
* Android-only; iOS returns `unsupported`.
