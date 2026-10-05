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
