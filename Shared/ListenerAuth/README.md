# ListenerAuth

The app-wide anonymous-auth stack, extracted from `MusicShareKit` as a pure move (WXYC/wxyc-ios-64#1099). `AuthenticationService`, `AuthNetworkClient`, `AuthSession`, the Keychain token and device-fingerprint storage, JWT decode, and the `MusicShareKit` composition root all live here now — consumed by Metadata's authed proxy, the On Tour fetcher, likes, and the request line alike.

## Naming

The composition-root enum is still called `MusicShareKit` (`MusicShareKitConfiguration.swift`), even though it now lives in the `ListenerAuth` module. That is deliberate and temporary: renaming it here would make this leaf a move *and* a rename at once. WXYC/wxyc-ios-64#1101 renames `enum MusicShareKit` -> `enum ListenerAuth` and `MusicShareKitConfiguration` -> `ListenerAuthConfiguration` once both `ListenerAuth` and the extracted `RequestLine` package (WXYC/wxyc-ios-64#1100) exist.

## Compatibility

`Shared/MusicShareKit` depends on this package and re-exports it via `@_exported import ListenerAuth` (`ListenerAuthReExport.swift`), so the eleven app-target files that `import MusicShareKit` keep compiling unchanged. That shim is temporary too — WXYC/wxyc-ios-64#1100 deletes it once `RequestLine` is extracted on top of `ListenerAuth` directly.

## Testing

`swift test --package-path Shared/ListenerAuth` (host-runnable; registered in `WXYC.xctestplan` and both affected-tests scripts). Run with `WXYC_SKIP_KNOWN_FLAKES` unset on the host path — the Keychain-backed suites (`KeychainTokenStorageTests`, `DeviceFingerprintTests`) need real Keychain access and are skipped on the simulator path via `-skip-testing:ListenerAuthTests`, where the SPM unit-test bundle has no Keychain entitlement.
