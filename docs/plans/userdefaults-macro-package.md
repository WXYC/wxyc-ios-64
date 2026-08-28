# A macro package to reduce UserDefaults-backed-variable boilerplate

Status: DRAFT — plan-reviewed 2026-07-23 (Approve with suggestions; all four findings incorporated below: realtime-audio-thread exclusion in Phase 3, macro-declaration home moved out of `Caching` to keep swift-syntax off non-consuming packages, `UserDefaults.standard` example fix, file-header/attribution note). No ticket filed, no implementation. Author-time investigation grounded in the current tree (patterns surveyed across ~30 files / ~55 keys; `AnalyticsMacros` used as the structural template).

Issue: none yet. This plan is the scoping artifact; a ticket + epic follow if approved.

## Problem

The app has many variables persisted to `UserDefaults`, and each one is written out by hand three times: a key constant, a `didSet` that writes the value, and a matching load line in the type's `init`. `VisualizerDataSource` (`Shared/PlayerHeaderView/Sources/PlayerHeaderView/VisualizerDataSource.swift:74`–`248`) and `OnAirDebugState` (`Shared/DebugPanel/Sources/DebugPanel/OnAirDebugState.swift:25`–`135`) are the worst offenders — 9 and ~15 persisted properties respectively, each repeating the same three-part shape. Across the repo that is roughly **55 distinct `forKey:` string literals over ~30 files**, dominated by a handful of `@Observable` settings/debug classes.

The desired end state: a single-line attribute at the property declaration replaces the key constant + `didSet` + init-load triple, with the value still (a) routed through the injected `DefaultsStorage` seam (not `UserDefaults.standard` directly, per `docs/swift-style.md:17`) and (b) observable so SwiftUI views update. The mechanism is a local Swift macro package modeled on the existing `Shared/AnalyticsMacros/`.

## What scoping turned up (reframes the request)

Three findings change what "a macro to reduce UserDefaults boilerplate" can actually mean here. None is visible from the request; all come from reading the code and the Swift macro model against it.

### Finding 1 — the boilerplate isn't "UserDefaults access," it's *injected, observable* access

The blessed pattern is not `UserDefaults.standard.set(...)`. It is: a type holds an injected `private let defaults: DefaultsStorage` (`Shared/Caching/Sources/Caching/DefaultsStorage.swift:16`, `extension UserDefaults: DefaultsStorage` at `:47`, test double `InMemoryDefaults`), and each persisted property reads/writes *that* seam so tests can substitute an in-memory store and run in parallel. Suite selection (standard vs. the App Group `UserDefaults.wxyc` = `group.wxyc.iphone`, `Shared/Caching/Sources/Caching/UserDefaults+WXYC.swift:43`) is expressed by *which* store is injected, not by the call site. So the macro cannot just hardcode `UserDefaults.standard` like a naive `@AppStorage` clone — it has to emit code against a conventional injected `defaults` member. That is the whole reason a macro (which can reference `self.defaults`) is a better fit here than a `@propertyWrapper` (which can't cleanly reach the enclosing instance's injected store — see [Alternative considered](#alternative-considered-a-property-wrapper)).

### Finding 2 — the high-value targets are all `@Observable`, and that dictates the macro's *only* viable shape

The three-part boilerplate concentrates in `@Observable` classes: `VisualizerDataSource`, `OnAirDebugState`, `DebugHUDState` (`Shared/DebugPanel/Sources/DebugPanel/DebugHUDState.swift:20`), `WallpaperDebugState`, `OnTourForYouSeedDebugState`, `OnTourShowsDebugState`. That is not incidental — it forces the macro's design:

- `@Observable` already rewrites every stored property into a computed get/set backed by `_$observationRegistrar` (via its own `@ObservationTracked` accessor macro).
- Swift does **not** allow two accessor macros to both supply accessors for one property. So a "light-touch" macro that merely *injects a `didSet`* cannot compose with `@Observable` — `@Observable` has already claimed the accessors. (A `didSet`-injecting macro only works on *non*-`@Observable` types, which are the already-DRY injected services — low value.)
- Therefore, on the types that matter, the macro **must take over the accessors entirely**: mark the property `@ObservationIgnored` (so `@Observable` leaves it alone), and generate a get/set that both touches `DefaultsStorage` *and* manually calls `access(keyPath:)` / `withMutation(keyPath:)` on `_$observationRegistrar` so SwiftUI observation still fires. This is the proven recipe used by the community `ObservableUserDefault` macro, but it couples the generated code to `@Observable`'s synthesized registrar symbol — the single real risk of this project (see [Risks](#risks--open-questions)).

Framing that makes the scope legible: **this macro is `@AppStorage` for `@Observable` model classes, backed by the injected `DefaultsStorage` seam instead of a hardcoded `UserDefaults`.**

### Finding 3 — Swift macros are syntactic, and the persisted properties aren't all primitives

Three properties of the real call sites break a naive "read/write the value" macro, and each has to be handled explicitly because a macro sees *syntax*, never *types*:

1. **`init`-load can't be reached.** A macro cannot inject statements into a hand-written `init`. The init-load block — e.g. `VisualizerDataSource.swift:208`–`248`, the single largest chunk of boilerplate — can only be eliminated by making the property **computed over the store** (read lazily on access), not stored-and-loaded-once. That is a deliberate semantic change: every read hits the store. For `UserDefaults`/`InMemoryDefaults` that is a cheap in-memory dictionary read, so it is acceptable — and it deletes the init-load entirely. But it means the default value moves **into the macro argument** (a computed property may not carry an `= default` initializer), so the call site is `@ObservableDefault("key", default: false) var showFPS: Bool`, not `... var showFPS = false`.

2. **Enums stored as `.rawValue`.** `fftNormalizationMode.rawValue` / `displayProcessor.rawValue` (`VisualizerDataSource.swift:124`, `:150`), `PlayerControllerType`, `PlaylistAPIVersion`, etc. are `RawRepresentable` persisted as their raw string/int. A macro can't *tell* a type is `RawRepresentable` — it only has the type name as syntax. So raw-value encoding must be **opt-in at the call site** (e.g. a `@RawObservableDefault` variant or a `strategy:` argument), not inferred.

3. **Codable JSON blobs.** `AdaptiveProfileStore` (`Shared/Wallpaper/.../Throttling/AdaptiveProfileStore.swift:61`–`90`) and the `ThemeConfiguration` mesh palettes (`Shared/Wallpaper/.../ThemeConfiguration.swift:338`) `JSONEncoder().encode(...)` into `Data`. Same syntactic limitation; a separate `@CodableDefault` would be needed. **Out of v1 scope.**

4. **Properties with side effects in `didSet`.** Several `didSet`s do more than persist: `signalBoost` clamps to `0.1...10.0` (`VisualizerDataSource.swift:106`–`113`), `displayProcessor` cascades processor enables (`:150`–`163`), `fftNormalizationMode` calls `fftProcessor.setNormalizationMode` (`:124`–`126`). A macro that owns the accessors can't also host arbitrary user logic. These **stay hand-written** (or the extra logic is refactored out). Of `VisualizerDataSource`'s 9 persisted properties, ~5 fall here — so that file is only *partially* addressable.

## Realistic addressable surface

Of the ~55 keys / ~50-60 persisted "blocks" the survey found, the macro cleanly serves a specific slice:

| Bucket | Rough count | Macro fit |
|---|---|---|
| `@Observable` debug/settings classes, **pure primitive** persist (`OnAirDebugState` ~15, `DebugHUDState`, `WallpaperDebugState`, the On-Tour debug states) | ~20-25 | **Clean win** — the v1 sweet spot |
| `@Observable`, primitive but with side-effecting/clamping `didSet` (much of `VisualizerDataSource`) | ~10 | **Partial** — only the pure props migrate; side-effecting ones stay manual |
| Enum-as-`.rawValue` on `@Observable` types | ~6 | Fast-follow (raw-value opt-in variant) |
| Injected services already DRY (`ReviewRequestService` `Shared/AppServices/.../ReviewRequestService.swift:28`, `SpotlightDonationService`, the `persist`/`clearPersisted` enum triads `Shared/Playback/.../PlayerControllerType.swift:24`) | ~10 | **Leave alone** — already tidy, different shape |
| `@AppStorage` in SwiftUI views (`ThemeDebugPopoverContent`, `PlayButton`) | ~10 | **Leave alone** — Swift's own macro already covers these |
| Codable JSON blobs (`AdaptiveProfileStore`, theme meshes) | ~4 | Out of scope (would need `@CodableDefault`) |

So the honest payoff is the pure-primitive `@Observable` debug/settings classes — real, but concentrated, not the whole 55-key surface. One migration wrinkle to note: `OnAirDebugState` and the other Pattern-C classes currently hit `UserDefaults.standard` **directly** (no injected member — a `docs/swift-style.md:17` violation). Migrating them to the macro *requires first adding* an injected `private let defaults: DefaultsStorage` member and threading it through `init`. That is a welcome two-birds cleanup, but it means those migrations are not purely mechanical.

## The design decision: the macro's shape

**Chosen: an accessor macro that makes the property a computed proxy over `DefaultsStorage`, coordinating manually with `@Observable`.** This is the only shape that composes with `@Observable` (Finding 2) and the only one that also eliminates the init-load (Finding 3.1).

Call site (on an `@Observable` type that holds `private let defaults: DefaultsStorage`):

```swift
@Observable
final class OnAirDebugState {
    @ObservationIgnored private let defaults: DefaultsStorage
    init(defaults: DefaultsStorage = UserDefaults.standard) { self.defaults = defaults }

    // before: key constant + didSet + init-load line, times N
    // after:
    @ObservableDefault("OnAirDebug.indicatorHue", default: 0.33)
    @ObservationIgnored
    public var indicatorHue: Double
}
```

Expansion (schematic):

```swift
public var indicatorHue: Double {
    get {
        _$observationRegistrar.access(self, keyPath: \.indicatorHue)
        return defaults.object(forKey: "OnAirDebug.indicatorHue") as? Double ?? 0.33
    }
    set {
        _$observationRegistrar.withMutation(of: self, keyPath: \.indicatorHue) {
            defaults.set(newValue, forKey: "OnAirDebug.indicatorHue")
        }
    }
}
```

Notes that the plan commits to:
- **Two attributes at the call site** (`@ObservableDefault(...)` + `@ObservationIgnored`). The second is mandatory so `@Observable` doesn't also try to generate accessors and collide. The macro's own diagnostics should detect a missing `@ObservationIgnored` on an `@Observable` type and emit a fix-it, since the raw compiler error ("invalid redeclaration of accessor") is opaque.
- **Default moves into the argument** (`default:`), because the property is now computed and can't carry `= 0.33`. Explicit `: Double` type annotation is required.
- **Store member is a convention** (`defaults`). v1 hardcodes the name `defaults`; if a type uses a different member the macro emits a diagnostic. (A `store:` argument to override the member name is a possible fast-follow, but every current call site already names it `defaults`.)
- **Keys stay explicit string literals** — never derived from the property name. The keys are a persistence contract; a silent derivation would orphan every user's stored value on a rename. This is a hard data-safety rule, not a preference.
- **Non-`@Observable` types** can use the same macro; the generated `access`/`withMutation` lines are simply omitted when the type isn't `@Observable`. (Detecting `@Observable`-ness syntactically is imperfect — see Risks. v1 may just always emit the registrar calls and require the attribute only be used on `@Observable` types, documenting that constraint.)

Variants, sequenced:
- **v1: `@ObservableDefault` for primitives** (`Bool/Int/Double/Float/String`).
- **Fast-follow: raw-value opt-in** — either `@RawObservableDefault` or `@ObservableDefault("key", default: .fft, strategy: .rawValue)` — to cover the enum settings, emitting `.rawValue` on write and `Type(rawValue:) ?? default` on read.
- **Deferred: `@CodableDefault`** for JSON blobs. Explicitly out of scope until the primitive/raw path is proven.

## Package structure (mirror `AnalyticsMacros` exactly)

The scaffolding is a solved problem — `Shared/AnalyticsMacros/` is the working template, and this package copies its shape verbatim. Proposed name `WXYCDefaultsMacros` (plugin `WXYCDefaultsMacrosPlugin`).

- **Two targets, one product**: a `.macro("WXYCDefaultsMacrosPlugin", dependencies: [SwiftSyntax, SwiftSyntaxMacros, SwiftCompilerPlugin, SwiftSyntaxBuilder])` holding the implementation + a `@main struct: CompilerPlugin { providingMacros: [...] }`, plus the `.target("WXYCDefaultsMacros")` re-export library that depends on the plugin and is the *only* exported product. Unlike `AnalyticsMacros`'s comment-only shim, this library is *not* empty — it hosts the `public macro @ObservableDefault(...) = #externalMacro(...)` declaration (see the declaration-home decision below), so adopting packages import exactly this one library.
- `// swift-tools-version: 6.2`, `import CompilerPluginSupport`, platforms `.iOS("18.4"), .watchOS(.v11), .macOS(.v15)`.
- swift-syntax pinned `"509.0.0"..<"603.0.0"`, which resolves to `602.0.0` — matching the workspace-wide pin already in `Shared/AnalyticsMacros/Package.resolved` and the app-level `Package.resolved`. Do not introduce a second swift-syntax version.
- **Macro declaration lives in the macro package's own re-export library — NOT in `Caching`.** `AnalyticsMacros` puts the `public macro ...() = #externalMacro(module: "...Plugin", type: "...")` declaration in the *consumer* library (`Analytics`), leaving the macro package's shim empty. This plan does the opposite for a deliberate reason: hosting the declaration in `Caching` would thread swift-syntax into every package that depends on `Caching` — 10 of them (`ColorPalette DebugPanel AppServices Metadata Artwork MusicShareKit PlayerHeaderView Playlist Playback Wallpaper`) — even though most (`ColorPalette`, `Metadata`, `Artwork`, ...) will never use the macro. Today swift-syntax reaches only the `Analytics` consumers, and this plan keeps that footprint tight. So the `public macro @ObservableDefault` declaration goes in the macro package's own re-export `.target("WXYCDefaultsMacros")` (the declaration needs no `Caching` type — its generated code just calls `defaults.set(...)`/`object(forKey:)` as member expressions), and **only the migration-target packages** (`DebugPanel`, `PlayerHeaderView`, and any other package whose classes actually adopt the macro) take the `.package(path: "../WXYCDefaultsMacros")` dependency + `import WXYCDefaultsMacros` at the call sites. `Caching` stays swift-syntax-free. The one cost is a new `import WXYCDefaultsMacros` line at each adopting call site (alongside the `import Caching` they already have) — cheap, and scoped to exactly the packages that opt in.
- **No `project.pbxproj` edit.** `AnalyticsMacros` has **zero** pbxproj references (`grep -c AnalyticsMacros project.pbxproj` → 0); it flows into the app transitively through `Analytics`. `WXYCDefaultsMacros` flows in the same way — transitively through whichever migration-target package (e.g. `DebugPanel`, `PlayerHeaderView`) adopts it. Only if resolution genuinely fails would a `XCLocalSwiftPackageReference` be added, following the `docs/project-structure.md` pbxproj hand-edit playbook — kept off the critical path.
- **File headers / attribution.** Every new file (plugin implementation, re-export shim, the `@ObservableDefault` declaration, tests) carries the standard header enforced by `scripts/hooks/header-check.sh` (`docs/file-headers.md`) — commits are blocked without it — with the "Created by" line reading **Jake Bromberg** (the existing `AnalyticsEventMacroTests.swift:7` "Created by Claude" line is a slip to avoid repeating, per the anonymity rule).
- **Tests**: XCTest + `SwiftSyntaxMacrosTestSupport`, `#if canImport(WXYCDefaultsMacrosPlugin)` guard with a skip fallback, a `testMacros` name→type map, and `assertMacroExpansion` cases — exactly the shape of `AnalyticsEventMacroTests.swift`.

## Phased runway

Each phase is independently shippable and PR-sized (org rule: ≤1000 lines). Each gets its own worktree (worktree before any code, per the git workflow). Phase 0 is a de-risking spike that gates the rest.

| Phase | Deliverable |
|---|---|
| 0 — spike | A throwaway single-file macro proving the `@Observable` + `_$observationRegistrar` coupling: one `@ObservableDefault` property on a real `@Observable` class, a SwiftUI view that observes it, and a test proving a write both persists and triggers observation. **Gate: if the registrar coupling is fragile or the generated code doesn't observe, stop and reconsider (or fall back to a hand-written base type).** |
| 1 — package | Stand up `Shared/WXYCDefaultsMacros/` (mirror `AnalyticsMacros`), the `@ObservableDefault` declaration in `Caching`, primitive support, `assertMacroExpansion` tests, diagnostics (missing `@ObservationIgnored`, missing `defaults` member, non-literal key). |
| 2 — migrate the clean win | Convert the pure-primitive `@Observable` debug/settings classes: `OnAirDebugState` (adding the injected `defaults` member as part of the swap), `DebugHUDState`, `WallpaperDebugState`, the On-Tour debug states. Existing tests are the regression guard; add per-class round-trip tests through `InMemoryDefaults`. |
| 3 — raw-value variant | Add the `.rawValue` opt-in and migrate the enum settings (`fftNormalizationMode`, `displayProcessor`, and the pure-persist enum properties). Partial-migrate `VisualizerDataSource` (pure props only; side-effecting ones **and any property read on the audio thread** documented as intentionally hand-written — see the realtime-safety note below). |
| 4 — document | Add a `docs/` topic doc ("persisted state") describing the macro, the `defaults`-member convention, the explicit-key data-safety rule, and what deliberately stays hand-written (side-effecting `didSet`s, Codable blobs, the already-DRY services). Add a one-line `CLAUDE.md` router entry. Cross-reference `docs/swift-style.md`. |

Phase 2 is the deliverable that justifies the package; Phases 3–4 are follow-ons. `@CodableDefault` is explicitly *not* on this runway.

**Realtime-safety carve-out for Phase 3 (hard exclusion, not a spot-check).** The macro's core semantic change (Finding 3.1) makes a migrated property *computed over the store* — every read performs a `DefaultsStorage.object(forKey:)`, which for `UserDefaults` acquires a lock. `VisualizerDataSource.processBuffer` runs on the **realtime audio thread** (`VisualizerDataSource.swift:67`, `:254`) and reads `signalBoost` and `signalBoostEnabled` there (`:262`–`263`). Migrating those two to computed properties would put a lock acquisition in the audio callback — a real-time-safety violation, not a performance nuance. **Rule: `signalBoost` and `signalBoostEnabled` (and any future property read inside `processBuffer`) stay stored-and-cached and are never macro-migrated.** They keep their hand-written `didSet`-persist + init-load. This is a strict exclusion on top of the side-effecting-`didSet` exclusion, and it further narrows what Phase 3 touches in `VisualizerDataSource` — reinforcing that this file is only partially addressable.

## TDD

- **Phase 1** is macro-expansion TDD: write `assertMacroExpansion` cases first (primitive get/set, default-value placement, the emitted registrar calls, each diagnostic) and implement the macro to satisfy them — the same red/green loop `AnalyticsEventMacroTests.swift` uses.
- **Phase 0/2** need a *behavioral* test the expansion tests can't give: `assertMacroExpansion` checks generated *source*, not that the property actually persists and observes at runtime. So each migrated class gets a round-trip test against `InMemoryDefaults` (set → new instance on the same store → reads back; and a mutation fires observation), proving the seam and the registrar wiring end to end.

## Alternative considered: a property wrapper

A `@propertyWrapper Persisted<Value>` using the `subscript(_enclosingInstance:storage:)` enclosing-self pattern would need **no** swift-syntax dependency and no new package. Rejected for v1:
- It hits the *same* `@Observable` wall — property wrappers on observed stored properties are disallowed/awkward, and the whole value proposition is the `@Observable` classes.
- Enclosing-self subscript access is a semi-private language corner.
- It still can't reach into a hand-written `init` to eliminate the init-load.

Since the payoff is entirely in the `@Observable` slice, the wrapper doesn't clear the bar the macro clears. The macro is the right tool *if* anything is built — but the spike (Phase 0) is what decides whether to build at all.

## Effort estimate

- Phase 0 spike: ~0.5 day (the go/no-go).
- Phase 1 package + primitives + tests + diagnostics: ~1–1.5 days.
- Phase 2 migrate the debug-state classes: ~0.5–1 day (includes adding injected `defaults` members to the Pattern-C classes).
- Phase 3 raw-value variant + partial VisualizerDataSource: ~0.5 day.
- Phase 4 docs: ~0.25 day.

~2.5–3.5 days total for a genuinely useful v1 (Phases 0–2), with Phase 0 as an explicit off-ramp.

## Risks / open questions

- **`@Observable` registrar coupling (the one real risk).** The generated get/set reference `_$observationRegistrar`, a symbol synthesized by `@Observable` and not part of a stable public contract. A future Swift/Observation change could break the generated code. Mitigation: Phase 0 spike proves it on the current toolchain before any package exists; the macro is one small file to update if the symbol shape changes; and the fallback (a hand-written non-macro base or accepting the boilerplate) is always available. This risk is *why* the plan leads with a spike rather than the package.
- **Detecting `@Observable`-ness syntactically.** A macro can't reliably know whether the enclosing type is `@Observable` (it sees attributes as syntax, and `@Observable` may be applied elsewhere). v1 sidesteps this by *always* emitting the registrar calls and documenting that `@ObservableDefault` is for `@Observable` types; a non-observable variant is a later refinement if needed.
- **Semantic change: computed vs. stored — with a realtime-thread hazard.** Migrated properties become computed-over-the-store (read on every access) instead of stored-and-cached. For the cold debug/settings classes (Phase 2) this is a cheap dictionary read and harmless. But it is an outright hazard for any property read on the realtime audio thread: `VisualizerDataSource.processBuffer` reads `signalBoost`/`signalBoostEnabled` per audio buffer, so migrating those would inject a `UserDefaults` lock acquisition into the audio callback. This is why Phase 3 carries a **hard exclusion** for audio-thread-read properties (see the realtime-safety carve-out under the runway), not merely a spot-check. Any candidate property must be confirmed off the realtime path before migration.
- **Payoff is concentrated, not broad.** After excluding side-effecting `didSet`s, Codable blobs, already-DRY services, and SwiftUI `@AppStorage`, the clean surface is ~20-25 properties in a handful of files. The plan is honest that this is a quality/consistency win on the debug/settings classes, not a sweeping 55-site reduction.
- **swift-syntax pin drift.** Keep the new package on the workspace's `602.0.0` resolution; a divergent pin would pull a second swift-syntax build into the graph.
