---
issue: WXYC/wxyc-ios-64#374
title: Rearchitect build-config analytics — implicit per-event stamping via xcconfig
branch: worktree-374-build-type-stamping
strategy: single PR, dual-write, no insight PATCH this round
---

# Goal

Replace the three hand-written `buildConfiguration()` helpers (in `WXYC/iOS/WXYCApp.swift`, `WXYC/WatchXYC/WatchXYCApp.swift`, `WXYC/WXYC TV/WXYCTVApp.swift`) and the `buildConfiguration: String` parameter on `AnalyticsBootstrap.start(...)` with an xcconfig-sourced, Info.plist-substituted value that the analytics layer reads once at runtime and stamps onto every captured event. Single source of truth: the build configuration itself, not Swift code that mirrors it.

# Why now

The current design has three problems:

1. **Drift risk** — the `#if DEBUG / #elseif TEST_FLIGHT / #else` ladder must be re-implemented in every app target (three places today). Adding a new target means adding a new helper. Removing or renaming a configuration means hunting through Swift code instead of editing build settings.
2. **Coverage is asymmetric** — only `AppLaunch` carries a `buildType: String` field (which `@AnalyticsEvent` snake-cases to `build_type` on the event property dict). Other structured events do not. The actual filter that all 9 PostHog consumers depend on is the `"Build Configuration"` *super-property* registered in `AnalyticsBootstrap.start`, which is independent of any event's typed schema. The two stamping mechanisms have diverged.
3. **TestFlight is silently coalesced.** The current `buildConfiguration()` ladder collapses both `TestFlight` and `Debug TestFlight` configurations to whatever the `TEST_FLIGHT` swift flag controls. Production data confirms only `"Debug"` and `"Release"` values are seen in the wild; `"TestFlight"` and `"Debug TestFlight"` aren't differentiated, and TestFlight events are likely being bucketed as `"Release"`. The new design fixes this by sourcing the value from the configuration name directly.

# Evidence (from PostHog inventory, 2026-06-01)

| Surface | Consumers of `"Build Configuration"` |
|---|---|
| Insights | 9 (4 pinned to dashboards 339917, 387216, 1021025, 1021034; 5 unpinned) |
| Dashboards | 0 directly (4 indirectly via insight tiles) |
| Cohorts | 0 |
| Feature flags | 0 (3 flags exist, none reference the key) |
| Experiments | 0 |
| Actions | 0 |

All 9 insights filter identically: `Build Configuration is_not ["Debug"]`. Three of them have a 180-day lookback (App Launch by OS Version, Domestic Listeners by Play Count copy, International Listeners by Play Count). One has 60-day lookback. The rest are ≤30-day.

**Value distribution (30 days, ~280k events):** `Release` 62.8%, `<NULL>` 31.5%, `Debug` 5.5%. The 31.5% NULL bucket is mostly PostHog SDK auto-captures (`Application Installed`, `$feature_flag_called`, etc.), PostHog AI built-ins (`$ai_generation`, `$ai_span`, `$ai_trace`), and the Widget extension (`getTimeline`, `getSnapshot`). The current super-prop is registered only in the main app target's `AnalyticsBootstrap.start`, so events fired from extensions or PostHog's own SDK auto-capture path are not stamped. **Closing this gap is out of scope for #374** — the new design preserves current coverage parity.

`build_type` already exists in production data on 477 AppLaunch events in the last 30d (all `"Debug"`), because `@AnalyticsEvent` snake-cases the `buildType: String` field. This means the namespace is already established and the value type is already validated.

# Strategy: single PR with dual-write, no insight PATCH

The original plan called for an atomic PATCH of the 9 insights to filter on `build_type` instead of `Build Configuration`, in the same PR as the code change. The PostHog inventory rules that out because three insights have a 180-day lookback — atomically swapping the filter key would lose 180 days of historical data on those dashboards, which is not recoverable (PostHog doesn't allow event-property backfill).

The revised approach:

| Decision | Rationale |
|---|---|
| **Keep the `register(["Build Configuration": ...])` super-property call** in `AnalyticsBootstrap.start`, sourced from the new Info.plist value | Backward compatibility: all 9 insights continue working with zero PostHog state changes |
| **Add per-event `build_type` stamping** in `StructuredPostHogAnalytics.capture` | Forward path: every event now carries `build_type`, so future insights and the Stage 2 PATCH have clean ground to stand on |
| **Drop the three `buildConfiguration()` helpers and the `buildConfiguration:` parameter** | Architectural goal achieved: build value comes from the xcconfig, not from Swift literal mirrors |
| **Drop the `buildType: String` field on `AppLaunch`** | Now redundant — the universal stamping covers it |
| **Do not PATCH any PostHog insight in this PR** | Insight PATCH is decoupled into a Stage 2 follow-up issue, to be filed in this PR. Stage 2 ships ~60 days after Stage 1 merges, by which point all rolling-window insights (including the 180d ones) have populated `build_type` for their full lookback range |

Dual-write cost: a single string property (~20 bytes) added to every event for ~60 days. At ~14k events/day, total ~24 MB of redundant data. Negligible.

# Concrete changes

## Build settings (Info.plist `$(CONFIGURATION)` substitution)

**Implementation note** (revised from the original draft): the xcconfig-conditional approach (`WXYC_BUILD_TYPE[config=...]` + `INFOPLIST_KEY_WXYC_BUILD_TYPE`) does not work in this project for two structural reasons surfaced during implementation:

1. **The `WXYC/Configuration/*.xcconfig` files are not wired as base configurations on any target.** They appear in `WXYC.xcodeproj/project.pbxproj` only as `membershipExceptions` on a `PBXFileSystemSynchronizedRootGroup` (i.e., as tracked files), not as `baseConfigurationReference` on any build configuration. Settings added to them have zero effect today. Wiring them up would require pbxproj edits across multiple targets and is its own initiative.
2. **`INFOPLIST_KEY_<CustomKey>` only injects into auto-generated Info.plists.** All three app targets resolve to `GENERATE_INFOPLIST_FILE = NO` with a manual `INFOPLIST_FILE` path; the prefix has no effect on manual plists.

**Final approach:** add `<key>WXYC_BUILD_TYPE</key><string>$(CONFIGURATION)</string>` directly to each of the three manual Info.plists. `$(CONFIGURATION)` is always available during Info.plist preprocessing and resolves to the exact configuration name string. No xcconfig touch needed; no project.pbxproj touch needed.

Three files updated:

| Target | Info.plist path |
|---|---|
| WXYC (iOS) | `WXYC/iOS/Assets/Info.plist` |
| WatchXYC | `WXYC/WatchXYC/WatchXYC-Info.plist` |
| WXYC TV | `WXYC/WXYC TV/WXYC-TV-Info.plist` |

Each gets:
```xml
<key>WXYC_BUILD_TYPE</key>
<string>$(CONFIGURATION)</string>
```

**Resulting values per configuration (verified by per-config `xcodebuild build` + `PlistBuddy` against the built `Info.plist`):**

| Configuration | WXYC_BUILD_TYPE value |
|---|---|
| `Debug` | `Debug` |
| `Debug TestFlight` | `Debug TestFlight` |
| `TestFlight` | `TestFlight` |
| `Release` | `Release` |
| `Release (Active Arch)` | `Release (Active Arch)` |

`Release (Active Arch)` is a developer-local fast-build variant of Release. The new design distinguishes it from regular Release in metrics, where the previous Swift helper coalesced both to `"Release"`. Pollution risk from a dev-machine `Release (Active Arch)` build reaching production PostHog is bounded and easily filterable; if it becomes noisy, a one-line Swift normalization can collapse it back (out of scope for this PR).

The `WXYC/Configuration/*.xcconfig` files are left untouched. Wiring them up as base configurations would be a worthwhile cleanup but is a separate concern that would touch `project.pbxproj` UUIDs (per `docs/project-structure.md`'s pbxproj fragility playbook).

## Swift analytics layer

### `Shared/Analytics/Sources/Analytics/AnalyticsBootstrap.swift`

Drop the `buildConfiguration` parameter. Read the value from `Bundle.main.infoDictionary["WXYC_BUILD_TYPE"]` internally. Default to `"unknown"` if the key is missing — this should never happen in shipped code (it would indicate a build settings regression) but `"unknown"` is more diagnostic than a crash.

```swift
public static func start(apiKey: String, host: String) {
    let config = PostHogConfig(apiKey: apiKey, host: host)
    PostHogSDK.shared.setup(config)

    let buildType = (Bundle.main.infoDictionary?["WXYC_BUILD_TYPE"] as? String) ?? "unknown"
    PostHogSDK.shared.register(["Build Configuration": buildType])
}
```

The super-prop key remains `"Build Configuration"` (with space, exactly as today) so all existing insights, dashboards, and historical data continue to work without any PostHog-side change.

### `Shared/Analytics/Sources/Analytics/StructuredPostHogAnalytics.swift`

Read the build type once at init. Merge `["build_type": buildType]` into every event's properties before forwarding to PostHog. Typed event properties win on collision (defensive — no current event uses the `"build_type"` key as a typed field, but the merge order should be explicit).

```swift
public final class StructuredPostHogAnalytics: AnalyticsService, @unchecked Sendable {
    public static let shared = StructuredPostHogAnalytics()

    private let buildType: String

    private init() {
        self.buildType = (Bundle.main.infoDictionary?["WXYC_BUILD_TYPE"] as? String) ?? "unknown"
    }

    public func capture<T: AnalyticsEvent>(_ event: T) {
        var properties = event.properties ?? [:]
        // Stamp build_type unconditionally; typed event keys take precedence on collision.
        if properties["build_type"] == nil {
            properties["build_type"] = buildType
        }
        PostHogSDK.shared.capture(T.name, properties: properties)
    }
}
```

### `Shared/Analytics/Sources/Analytics/Events/AppLifecycleEvents.swift`

Drop the `buildType: String` field on `AppLaunch`. The auto-stamping in `StructuredPostHogAnalytics` covers it. After:

```swift
@AnalyticsEvent
public struct AppLaunch {
    public let hasUsedThemePicker: Bool

    public init(hasUsedThemePicker: Bool) {
        self.hasUsedThemePicker = hasUsedThemePicker
    }
}
```

`AppLaunchSimple` (used by watchOS/tvOS) is already field-less. No change.

### `Shared/Analytics/Tests/AnalyticsTests/EventNameStabilityTests.swift`

Already asserts `(AppLaunch.name, "app_launch")`. No change needed — the name is stable.

### `Shared/AnalyticsMacros/Tests/AnalyticsMacrosTests/AnalyticsEventMacroTests.swift`

The test fixture at lines 17-52 (`testBasicExpansion`) uses an `AppLaunch` struct with `hasUsedThemePicker: Bool` and `buildType: String`. Update the fixture to drop `buildType` (the macro behavior is unchanged; we just want a fixture that mirrors the new event shape). The macro itself doesn't change.

### App target files

| File | Lines | Change |
|---|---|---|
| `WXYC/iOS/WXYCApp.swift` | 77-80 | Drop `buildType: buildConfiguration()` arg in `AppLaunch(...)` call |
| `WXYC/iOS/WXYCApp.swift` | 224-230 | Drop `buildConfiguration:` arg in `AnalyticsBootstrap.start(...)` |
| `WXYC/iOS/WXYCApp.swift` | 264-272 | Delete `buildConfiguration()` helper |
| `WXYC/WatchXYC/WatchXYCApp.swift` | 24-28 | Drop `buildConfiguration:` arg in `AnalyticsBootstrap.start(...)` |
| `WXYC/WatchXYC/WatchXYCApp.swift` | 47-55 | Delete `buildConfiguration()` helper |
| `WXYC/WXYC TV/WXYCTVApp.swift` | 28-30 | **Bug fix in scope:** add `setUpAnalytics()` call in `init()` before the `capture(AppLaunchSimple())` line. Today `setUpAnalytics()` is defined but never called, so `PostHogSDK.shared.setup(...)` is never invoked on tvOS — events captured from this target are silently dropped. The refactor incidentally exposes this dead code, and fixing it now closes a one-line gap that would otherwise need a separate ticket |
| `WXYC/WXYC TV/WXYCTVApp.swift` | 33-37 | Drop `buildConfiguration:` arg in `AnalyticsBootstrap.start(...)` inside `setUpAnalytics()` |
| `WXYC/WXYC TV/WXYCTVApp.swift` | 40-48 | Delete `buildConfiguration()` helper |

# TDD test specifications

Per `CLAUDE.md`'s strict TDD requirement, each behavior change below has a failing test written *before* the corresponding implementation change. Tests use the swift-testing framework (`@Suite`/`@Test`), matching the existing pattern in `Shared/Analytics/Tests/AnalyticsTests/ErrorEventsTests.swift` and `EventNameStabilityTests.swift`.

## `Shared/Analytics/Tests/AnalyticsTests/AnalyticsBootstrapTests.swift` (new file)

```swift
import Foundation
import Testing
@testable import Analytics

@Suite("AnalyticsBootstrap")
struct AnalyticsBootstrapTests {
    @Test("start() compiles without buildConfiguration parameter")
    func startSignatureHasNoBuildConfigurationParameter() {
        // Compile-time guard: if the parameter is reintroduced, this call
        // fails to compile, which is the failure mode we want.
        let _: (String, String) -> Void = { apiKey, host in
            AnalyticsBootstrap.start(apiKey: apiKey, host: host)
        }
    }
}
```

Rationale: PostHog SDK setup has global side effects (sets `PostHogSDK.shared`) that make per-test isolation expensive. The compile-time check is the minimum that catches the actual contract change. The integration behavior (super-prop is registered with the Info.plist value) is verified post-merge via the manual smoke test below.

## `Shared/Analytics/Tests/AnalyticsTests/StructuredPostHogAnalyticsTests.swift` (new file)

```swift
import Foundation
import Testing
@testable import Analytics

@Suite("StructuredPostHogAnalytics build_type stamping")
struct StructuredPostHogAnalyticsTests {
    // Test fixture event with no typed build_type field; stamping should add one.
    struct PlainEvent: AnalyticsEvent {
        static let name = "plain_event"
        var properties: [String: Any]? { ["foo": "bar"] }
    }

    // Test fixture event that ALREADY declares a build_type key. The stamping
    // path must not clobber a typed event's explicit value.
    struct EventWithTypedBuildType: AnalyticsEvent {
        static let name = "event_with_typed_build_type"
        var properties: [String: Any]? { ["build_type": "typed_wins"] }
    }

    // Test fixture event with nil properties (the AnalyticsEventMacro path for
    // empty-property structs); stamping should still add build_type.
    struct EmptyEvent: AnalyticsEvent {
        static let name = "empty_event"
        var properties: [String: Any]? { nil }
    }

    @Test("captures a plain event with build_type stamped from Info.plist")
    func plainEventGetsBuildTypeStamped() throws {
        // The implementation reads Bundle.main.infoDictionary["WXYC_BUILD_TYPE"]
        // at init. In a test bundle that key is absent, so the stamp is "unknown".
        // We assert structurally — the key MUST be present in the merged dict.
        let captured = CapturingPostHogClient()
        let sut = StructuredPostHogAnalytics(client: captured, buildType: "TestFlight")
        sut.capture(PlainEvent())

        let last = try #require(captured.events.last)
        #expect(last.name == "plain_event")
        #expect(last.properties?["foo"] as? String == "bar")
        #expect(last.properties?["build_type"] as? String == "TestFlight")
    }

    @Test("typed event property wins on collision with stamped build_type")
    func typedEventBuildTypeWinsOverStamp() throws {
        let captured = CapturingPostHogClient()
        let sut = StructuredPostHogAnalytics(client: captured, buildType: "Release")
        sut.capture(EventWithTypedBuildType())

        let last = try #require(captured.events.last)
        #expect(last.properties?["build_type"] as? String == "typed_wins")
    }

    @Test("empty-property event still gets build_type stamped")
    func emptyEventGetsBuildTypeStamped() throws {
        let captured = CapturingPostHogClient()
        let sut = StructuredPostHogAnalytics(client: captured, buildType: "Debug")
        sut.capture(EmptyEvent())

        let last = try #require(captured.events.last)
        #expect(last.properties?["build_type"] as? String == "Debug")
    }
}

// Test seam: a protocol-shaped capture interface that the production class
// uses internally so tests can substitute an in-memory capturing client.
// Introduced as part of #374 to make stamping unit-testable; the production
// path remains a thin wrapper around PostHogSDK.shared.
final class CapturingPostHogClient: PostHogClientProtocol {
    struct Captured {
        let name: String
        let properties: [String: Any]?
    }
    private(set) var events: [Captured] = []
    func capture(_ name: String, properties: [String: Any]?) {
        events.append(.init(name: name, properties: properties))
    }
}
```

This necessitates introducing a small `PostHogClientProtocol` seam in `StructuredPostHogAnalytics.swift` (one method: `capture(_:properties:)`) with the production default routing to `PostHogSDK.shared`. The seam is the minimum scaffolding required to make the stamping behavior testable without standing up the full PostHog SDK. Per CLAUDE.md's "don't add error handling, fallbacks, or validation for scenarios that can't happen" — the seam is justified because the scenario (call site invokes capture; verify stamping) is exactly what we need to verify, not defensive scaffolding.

## `Shared/Analytics/Sources/Analytics/StructuredPostHogAnalytics.swift` (revised)

```swift
import Foundation
import PostHog

/// Production seam wrapping the PostHog SDK's capture API so the stamping
/// path is unit-testable. The only production implementation forwards to
/// PostHogSDK.shared.
protocol PostHogClientProtocol {
    func capture(_ name: String, properties: [String: Any]?)
}

private struct PostHogSDKClient: PostHogClientProtocol {
    func capture(_ name: String, properties: [String: Any]?) {
        PostHogSDK.shared.capture(name, properties: properties)
    }
}

public final class StructuredPostHogAnalytics: AnalyticsService, @unchecked Sendable {
    public static let shared = StructuredPostHogAnalytics()

    private let client: PostHogClientProtocol
    private let buildType: String

    /// Production initializer — reads build type from Info.plist.
    private convenience init() {
        let buildType = (Bundle.main.infoDictionary?["WXYC_BUILD_TYPE"] as? String) ?? "unknown"
        self.init(client: PostHogSDKClient(), buildType: buildType)
    }

    /// Test seam initializer. Explicitly `internal` so tests (via `@testable import`)
    /// can use it without exposing the seam to API consumers.
    internal init(client: PostHogClientProtocol, buildType: String) {
        self.client = client
        self.buildType = buildType
    }

    public func capture<T: AnalyticsEvent>(_ event: T) {
        var properties = event.properties ?? [:]
        if properties["build_type"] == nil {
            properties["build_type"] = buildType
        }
        client.capture(T.name, properties: properties)
    }
}
```

## `Shared/AnalyticsMacros/Tests/AnalyticsMacrosTests/AnalyticsEventMacroTests.swift`

Update the `testBasicExpansion` fixture (currently lines 17-52) to remove the `buildType: String` field. The macro behavior under test (auto-generating `name` and `properties` for a struct annotated `@AnalyticsEvent`) is unchanged.

After:
```swift
@AnalyticsEvent
public struct AppLaunch {
    public let hasUsedThemePicker: Bool
}
```
→
```swift
public struct AppLaunch {
    public let hasUsedThemePicker: Bool

    public static let name: String = "app_launch"

    public var properties: [String: Any]? {
        ["has_used_theme_picker": hasUsedThemePicker]
    }
}
```

# Verification

Per-configuration build + Info.plist inspection. Local script run by hand (not committed):

```bash
for cfg in 'Debug' 'Debug TestFlight' 'TestFlight' 'Release'; do
    xcodebuild \
        -project WXYC.xcodeproj \
        -scheme WXYC \
        -configuration "$cfg" \
        -destination 'platform=iOS Simulator,id=156E5217-1C62-4531-B8BE-B0299138F6DB' \
        -derivedDataPath build/ \
        build 2>&1 | tail -5
    PLIST=$(find build/Build/Products -name 'Info.plist' -path '*/WXYC.app/*' | head -1)
    echo "$cfg: $(/usr/libexec/PlistBuddy -c 'Print :WXYC_BUILD_TYPE' "$PLIST" 2>&1)"
done
```

Expected output:
```
Debug: Debug
Debug TestFlight: Debug TestFlight
TestFlight: TestFlight
Release: Release
```

If any configuration prints `unknown` or a different value, the xcconfig conditional is wrong — investigate before merging.

Unit tests:
- `swift test --package-path Shared/Analytics` — verify `StructuredPostHogAnalytics` stamping and `AnalyticsBootstrap` no-longer-requires-parameter.
- `swift test --package-path Shared/AnalyticsMacros` — verify the macro-expansion fixture update.

End-to-end PostHog smoke (manual, post-merge):
1. Launch a Debug build → confirm an `app_launch` event arrives with `"build_type": "Debug"` and the super-prop `"Build Configuration": "Debug"`.
2. Launch a TestFlight build via the TestFlight track → confirm `"build_type": "TestFlight"` and `"Build Configuration": "TestFlight"` (this will be the first time TestFlight is correctly differentiated in PostHog).

# What stays out of scope

Listed explicitly so the PR review doesn't churn on them:

- **No PostHog insight PATCH in this PR.** Filed as Stage 2 follow-up.
- **No widget/extension stamping coverage.** The Widget extension currently emits events without `Build Configuration`; the new `StructuredPostHogAnalytics` wrapper doesn't reach its event path. Widget analytics architecture is its own initiative (issue #372 addresses part of it).
- **No backfill of historical events.** PostHog doesn't permit event-property updates after ingestion; old events keep `Build Configuration` only, which is fine because the super-prop registration is preserved.
- **No removal of the `"Build Configuration"` super-property.** Stage 2 follow-up.
- **`buildConfigurationResult` property** — found in PostHog's property definitions list, but 0 events carry it (stale schema cruft). Not touched.

# Stage 2 follow-up — tracked as [WXYC/wxyc-ios-64#383](https://github.com/WXYC/wxyc-ios-64/issues/383)

After ~60 days of Stage 1 deployment (sufficient for the longest 180-day lookback insight to have its first 60-day buffer of dual-write events, after which the OR-filter trade-off can be re-evaluated):

1. PATCH all 9 PostHog insights (and any new ones referencing `Build Configuration`) to filter on `build_type` instead. For the three 180-day insights, the PATCH can either:
   - Use `(build_type is_not Debug)` and accept the 120-day pre-Stage-1 gap, or
   - Use an OR-filter `(build_type is_not Debug) OR (build_type is unset AND Build Configuration is_not Debug)` to preserve historical data.
2. Drop the `PostHogSDK.shared.register(["Build Configuration": ...])` call from `AnalyticsBootstrap.start`.
3. (Optional cleanup) After PATCH lands and metrics stabilize, hide or delete the `Build Configuration` property definition in PostHog's property catalogue.

# Risk assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| xcconfig conditional syntax doesn't substitute correctly for configs with spaces | Low (documented Xcode behavior) | Per-configuration build verification before merge |
| `INFOPLIST_KEY_*` injection collides with another setting | Very low | The key namespace is custom (`WXYC_BUILD_TYPE`); no Apple-reserved key |
| Reading `Bundle.main.infoDictionary` is slow enough to matter | Negligible | Read once at init, cached in property |
| `"build_type"` event property collides with future PostHog auto-stamp | Very low | The key is lowercase and namespace-free; PostHog's auto-stamped keys are `$`-prefixed |
| Stage 1 dual-write triggers PostHog ingestion or property-cap alert | Negligible | Adding one property to events; project has ~325 properties already, well under limits |
| Stage 2 PATCH gets forgotten | Medium | Filed as a tracked issue with a specific date trigger (Stage 1 merge + 60 days) |
| The `WXYCTVApp` `setUpAnalytics()` bug-fix introduces TestFlight/Release PostHog events that weren't being sent before | Low | tvOS analytics goes from "broken (events dropped)" to "working (events ingested)". The Stage 1 PostHog data shows TestFlight values are absent today — this fix is one of the contributing reasons. New traffic from this surface is by definition correct data, and adding it makes the existing dashboards more accurate, not less. If the volume is unexpectedly high and skews historical comparisons, the Stage 2 follow-up can include a brief annotation in PostHog explaining the inflection point |
