//
//  MusicShareKitConfiguration.swift
//  MusicShareKit
//
//  Configuration for MusicShareKit endpoints and behavior.
//
//  Created by Jake Bromberg on 12/22/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Analytics
import Caching
import Core
import Foundation
import Security

/// Configuration for MusicShareKit services.
/// Must be set before using RequestService or ShareExtensionView.
public struct MusicShareKitConfiguration {
    /// The URL for the request-o-matic service
    public let requestOMaticURL: String

    /// The base URL for the authentication API.
    /// Required for authenticated requests when the feature flag is enabled.
    public let authBaseURL: String?

    /// The Keychain access group to scope tokens to, or `nil` for the
    /// process default.
    ///
    /// Format is `<App ID prefix>.<group name>`. The App ID prefix is **not**
    /// necessarily the Team ID — assuming it was is what caused #996 — so do
    /// not write a literal here. Callers pass
    /// `AppConfiguration.keychainAccessGroup`, which reads the value the build
    /// system expanded; see `KeychainAccessGroup` for the full account.
    public let keychainAccessGroup: String?

    /// Provider for checking feature flag values.
    /// Used to determine if authentication is enabled.
    public let featureFlagProvider: FeatureFlagProvider?

    /// Defaults storage for storing debug overrides.
    /// Uses app group defaults for sharing between app and extensions.
    public let defaults: DefaultsStorage

    /// Analytics service for tracking events.
    public let analyticsService: AnalyticsService

    /// Storage for the stable per-device fingerprint sent as `X-Device-Fingerprint`
    /// on authenticated requests. Defaults to `KeychainDeviceFingerprintStorage`
    /// scoped to the same `keychainAccessGroup` as `KeychainTokenStorage`.
    /// Note that this does **not** currently mean main app and share extension
    /// see the same value — their App ID prefixes differ, so each resolves to
    /// its own group. Tracked in #1008.
    public let deviceFingerprintStorage: any DeviceFingerprintStorage

    public init(
        requestOMaticURL: String,
        authBaseURL: String? = nil,
        keychainAccessGroup: String? = nil,
        featureFlagProvider: FeatureFlagProvider? = nil,
        defaults: DefaultsStorage = UserDefaults.standard,
        analyticsService: AnalyticsService,
        deviceFingerprintStorage: (any DeviceFingerprintStorage)? = nil
    ) {
        self.requestOMaticURL = requestOMaticURL
        self.authBaseURL = authBaseURL
        self.keychainAccessGroup = keychainAccessGroup
        self.featureFlagProvider = featureFlagProvider
        self.defaults = defaults
        self.analyticsService = analyticsService
        self.deviceFingerprintStorage = deviceFingerprintStorage
            ?? KeychainDeviceFingerprintStorage(accessGroup: keychainAccessGroup)
    }
}

/// Global configuration storage for MusicShareKit
public enum MusicShareKit {
    // Safe because configuration is set once at app startup before any access
    nonisolated(unsafe) private static var _configuration: MusicShareKitConfiguration?
    nonisolated(unsafe) private static var _authService: AuthenticationService?
    nonisolated(unsafe) private static var _deviceFingerprint: String?
    /// True once we've attempted the inline retry-on-read for a failed
    /// eager init. Prevents `MusicShareKit.deviceFingerprint` from
    /// re-entering `storage.ensure()` (which does synchronous Keychain IO)
    /// on every request when the Keychain is wedged.
    nonisolated(unsafe) private static var _fingerprintRetryAttempted: Bool = false
    private static let fingerprintLock = NSLock()
    /// Backs `configure(_:)`'s once-per-process guard — see
    /// ``MusicShareKit/configure(_:)`` for why it exists (#956).
    ///
    /// `internal` rather than `private` so tests can assert the gate is
    /// still fresh before exercising it — a once-per-process guarantee that
    /// silently no-ops when something already tripped the gate would let its
    /// own regression test pass vacuously.
    static let configureGate = RunOnceGate()

    /// Counts reads of ``deviceFingerprint`` that arrived before
    /// `configure(_:)` ran (#998). Reported on that launch's
    /// `FingerprintModeResolvedEvent` — see the accessor's `_configuration`
    /// guard for why the access cannot report itself when it happens, and
    /// ``PrematureAccessCounter`` for why reading it does not reset it.
    ///
    /// `internal` rather than `private` so tests can record against the same
    /// API production uses. The accessor's guard is otherwise unreachable from
    /// this package's test target: `_configuration` is a process global, and
    /// once any suite in the process has configured MusicShareKit it never
    /// returns to nil.
    static let prematureFingerprintAccesses = PrematureAccessCounter()

    /// The current configuration. Fatal error if not set.
    public static var configuration: MusicShareKitConfiguration {
        guard let config = _configuration else {
            fatalError("MusicShareKit.configure() must be called before using MusicShareKit services")
        }
        return config
    }

    /// The shared authentication service, if authentication is configured.
    public static var authService: AuthenticationService? {
        _authService
    }

    /// The canonical `SessionTokenProvider` for every consumer site, eager
    /// or live-read.
    ///
    /// `Singletonia` is constructed from a SwiftUI stored-property
    /// initializer, which runs before `WXYCApp.init()` calls
    /// `configure(...)` — a construction site that reads `authService`
    /// directly at that point captures `nil` permanently, and every authed
    /// request it makes 401s with no recovery (#718). This facade resolves
    /// `authService` at each call instead, so handing it to a service at any
    /// construction time is safe and the nil-capture class of bug is
    /// unrepresentable rather than avoided per-site.
    ///
    /// Every call forwards to the same `AuthenticationService` actor
    /// instance, preserving its single-flight coalescing contract on
    /// `reauthenticate(previousToken:)` — nothing is cached here. Before
    /// `configure(...)` has run, calls throw
    /// `SessionTokenProviderError.notConfigured`.
    public static var tokenProvider: any SessionTokenProvider {
        DeferredSessionTokenProvider { authService }
    }

    /// The stable per-device fingerprint, or `nil` if it could not be loaded.
    ///
    /// Eager init in `configure(...)` is the authoritative path that closes
    /// the cross-process race (D3 in the iOS#351 plan). The inline retry here
    /// is a defensive backstop for the narrow window where `configure()` ran
    /// pre-first-unlock (e.g., a background-launched share extension) and the
    /// actual request happens after the user has unlocked the device. The
    /// retry fires AT MOST ONCE per process lifetime — otherwise every
    /// authenticated request would hammer the Keychain when the device is
    /// permanently wedged (locked daemon, missing entitlement, etc.).
    ///
    /// Reads that arrive before `configure(...)` has run return `nil` and are
    /// counted into ``prematureFingerprintAccesses``, which the next
    /// `reconfigure(_:)` reports on `fingerprint_mode_resolved_event` (#998).
    public static var deviceFingerprint: String? {
        fingerprintLock.lock()
        defer { fingerprintLock.unlock() }

        if let cached = _deviceFingerprint {
            return cached
        }

        // We've already tried the inline retry; respect the cached-nil
        // verdict so we don't repeatedly round-trip to securityd.
        if _fingerprintRetryAttempted {
            return nil
        }

        guard let config = _configuration else {
            // The pre-configure read (#998). Until #998 this returned nil with
            // no trace at all, which made "a caller reaches the fingerprint
            // before configure()" an unfalsifiable hypothesis in #996.
            //
            // It cannot capture analytics from here: the analytics service
            // lives on `_configuration`, which is exactly what is missing, and
            // `MusicShareKit.configuration` would `fatalError` rather than
            // help. So record it and let the next `reconfigure(_:)` fold the
            // total into that launch's `FingerprintModeResolvedEvent`. The
            // counter holds no reference to anything — no closure, no service,
            // no cycle — and has its own lock, so taking it while
            // `fingerprintLock` is held is a consistent ordering, never an
            // inversion.
            prematureFingerprintAccesses.record()
            return nil
        }

        _fingerprintRetryAttempted = true
        guard let value = try? config.deviceFingerprintStorage.ensure() else {
            // Retry burned. Downstream callers omit the header, ROM
            // proceeds-as-unauth, the listener can still request, the
            // ban-evasion vector temporarily opens until next launch.
            // Analytics already captured during the eager attempt in
            // configure(); don't double-emit.
            //
            // `FingerprintModeResolvedEvent` is bound by the same rule, in
            // both directions: this retry emits nothing when it fails, and
            // emits nothing when it SUCCEEDS either. One event per launch is
            // the budget (#998). The known cost is that a device whose eager
            // init failed and whose retry then recovered is reported as
            // `failed` for that launch — the mode describes what
            // configure(...) resolved, not what the process eventually got.
            return nil
        }
        _deviceFingerprint = value
        return value
    }

    /// Configure MusicShareKit with the required settings.
    ///
    /// Call this early in your app's lifecycle before using any MusicShareKit
    /// services. Idempotent per process from the second call onward: only
    /// the first call actually rebuilds `_configuration`, the device
    /// fingerprint, and `_authService` (via `reconfigure(_:)`); every later
    /// call in the same process is a no-op (#956). That makes it safe for a
    /// caller that runs on every presentation — the share extension's
    /// `ShareViewController.viewDidLoad` — to call this unconditionally: the
    /// first presentation's `AuthenticationService`, and whatever
    /// `cachedSession` it accumulates, is reused by every later
    /// presentation in the same process instead of being rebuilt from
    /// scratch (which would start each presentation from `cachedSession ==
    /// nil` and re-mint an orphaned anonymous user on a Keychain-miss
    /// device — the #948 fallback's precondition, broken).
    ///
    /// Tests that need a guaranteed rebuild with fresh doubles installed on
    /// every call should call `reconfigure(_:)` instead.
    public static func configure(_ configuration: MusicShareKitConfiguration) {
        configureGate.runOnce {
            reconfigure(configuration)
        }
    }

    /// Unconditionally (re)initializes MusicShareKit's global state —
    /// `_configuration`, the device fingerprint, and `_authService` — even
    /// if `configure(_:)` already ran once in this process.
    ///
    /// Reserved for tests: several `MusicShareKitTests` suites call this
    /// repeatedly within one test process and depend on the rebuild to
    /// install fresh doubles (analytics mocks, fingerprint/token storage
    /// doubles, etc.) on every call.
    ///
    /// Deliberately `internal`, not `public`: the package's test target
    /// reaches it through `@testable import`, while app and extension
    /// targets cannot see it at all. That makes #956's guarantee structural
    /// rather than conventional — a future `ShareViewController` edit can't
    /// autocomplete its way past the guard and silently reinstate #948's
    /// per-presentation rebuild. Production code calls the guarded
    /// `configure(_:)` — see its doc comment for why.
    static func reconfigure(_ configuration: MusicShareKitConfiguration) {
        _configuration = configuration

        // Eagerly materialize the device fingerprint BEFORE init'ing the auth
        // service so the fingerprint header is available on the very first
        // /sign-in/anonymous call.
        //
        // Eager (vs. lazy) is load-bearing: lazy initialization would let the
        // main app and share extension first-launch concurrently, both observe
        // an empty Keychain on their first read, and both write — Race A in
        // the iOS#351 plan. Eager init means whichever process runs configure()
        // second sees the value committed by the first via the atomic
        // add-or-reread inside ensure().
        //
        // This is also the once-per-launch emission site for
        // `FingerprintModeResolvedEvent` (#998). The do/catch below decides
        // only WHAT to report; the single capture after it is what makes
        // "exactly one event per configure, on every path" true by
        // construction rather than by convention. A resolved-mode metric that
        // only spoke up on failure would be indistinguishable from one that
        // had stopped reporting, which is the ambiguity that hid #996.
        fingerprintLock.lock()
        _fingerprintRetryAttempted = false  // fresh configure resets the retry budget
        let prematureAccessCount = prematureFingerprintAccesses.count
        let mode: DeviceFingerprintMode
        let osStatus: OSStatus
        var initFailure: String?
        do {
            let resolution = try configuration.deviceFingerprintStorage.resolve()
            _deviceFingerprint = resolution.value
            (mode, osStatus) = (resolution.mode, resolution.osStatus)
        } catch {
            _deviceFingerprint = nil
            initFailure = error.localizedDescription
            (mode, osStatus) = (.failed, keychainStatus(of: error))
        }
        fingerprintLock.unlock()

        // Captured outside the lock: `PostHogSDK.capture` is synchronous down
        // to a disk write, and every `deviceFingerprint` reader contends on
        // `fingerprintLock`. Nothing below touches the guarded globals.
        if let initFailure {
            configuration.analyticsService.capture(
                DeviceFingerprintInitFailedEvent(error: initFailure)
            )
        }
        configuration.analyticsService.capture(
            FingerprintModeResolvedEvent(
                mode: mode,
                osStatus: osStatus,
                prematureAccessCount: prematureAccessCount
            )
        )

        // Initialize auth service if auth is configured
        if let authBaseURL = configuration.authBaseURL {
            let storage = KeychainTokenStorage(
                accessGroup: configuration.keychainAccessGroup,
                analytics: configuration.analyticsService
            )
            _authService = AuthenticationService(
                storage: storage,
                networkClient: DefaultAuthNetworkClient(),
                baseURL: authBaseURL,
                analytics: configuration.analyticsService
            )
        }
    }

    /// The `OSStatus` a failed eager init should report on
    /// `FingerprintModeResolvedEvent`.
    ///
    /// `KeychainDeviceFingerprintStorage` only ever throws
    /// `AuthenticationError.keychainError`, so the fallback is unreachable from
    /// production; it exists because `DeviceFingerprintStorage` is a protocol
    /// and a conformer may throw anything. When it does fire, nothing is lost:
    /// the `DeviceFingerprintInitFailedEvent` captured alongside carries the
    /// error's full description.
    private static func keychainStatus(of error: Error) -> OSStatus {
        guard case .keychainError(let status)? = error as? AuthenticationError else {
            return errSecInternalError
        }
        return status
    }

    /// Checks if request line authentication is enabled via feature flag.
    ///
    /// A pure forward to `RequestLineAuthFeature.isEnabled(...)`, which owns
    /// the full 3-step priority order documented on that type — including
    /// step 3, "no provider was wired" — so every return path is captured in
    /// telemetry with no branch needed here (#1012).
    ///
    /// `configuration` is read once into a local rather than through three
    /// separate property accesses on the static `configuration`: it is a
    /// computed static unwrapping a `nonisolated(unsafe)` var, so reading it
    /// once per collaborator would let a `reconfigure(_:)` landing mid-call
    /// hand this call collaborators from different configurations (#848).
    ///
    /// Not captured in the Share Extension process: `PostHogSDK.setup` is
    /// never called there. Analytics bootstrap only runs from
    /// `AppBootstrap.swift`, `WatchXYCApp.swift`, and `WXYCTVApp.swift` —
    /// `ShareViewController.viewDidLoad` calls `configure(...)` but never
    /// bootstraps analytics — so `RequestLineFeatureFlagEvaluatedEvent` is
    /// inert on that call site even though `ShareExtensionView` reaches this
    /// function via `RequestService.sendRequest` (#1012).
    ///
    /// - Returns: `true` if authentication should be used, `false` otherwise.
    public static func isAuthEnabled() -> Bool {
        let config = configuration
        return RequestLineAuthFeature.isEnabled(
            featureFlagProvider: config.featureFlagProvider,
            defaults: config.defaults,
            analytics: config.analyticsService
        )
    }
}
