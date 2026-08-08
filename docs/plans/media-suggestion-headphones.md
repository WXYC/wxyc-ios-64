# Plan: Make WXYC eligible for iOS media suggestions (headphone-connect tile)

## Problem

When a user connects headphones (or CarPlay), iOS offers a "play" suggestion for media apps on the Home Screen Siri Suggestions row and the Lock Screen. WXYC never appears there. Comparable stations do — a single launch of KEXP is enough for it to be suggested the following day.

WXYC already donates `INPlayMediaIntent`, which is the part that *looks* like it should be sufficient. It is not. The media-suggestion engine keys off three additional things, none of which the app does.

### Current state

| Piece | Where | Status |
|---|---|---|
| `INPlayMediaIntent` donation at launch | `WXYC/iOS/WXYCApp.swift:375` (built), `:95` (called) | Present. Media item id `"Play WXYC"`, `resumePlayback: false`, composited station artwork |
| `INPlayMediaIntent` donation on play | `Shared/Playback/Sources/PlaybackAPI/AudioPlayerController.swift:1604` (built), `:651` (called) | Present. Media item id `"WXYC"`, `resumePlayback: true`, `artwork: nil` |
| `NSUserActivityTypes` declaring `INPlayMediaIntent` | `WXYC/iOS/Assets/Info.plist:79` | Present |
| Continuation handling of a replayed donation | `WXYC/iOS/AppLifecycleModifier.swift:144` | Present — but requires a **foreground app launch** |
| `INMediaUserContext` | — | **Absent** |
| `INUpcomingMediaManager` | — | **Absent** |
| SiriKit `INPlayMediaIntent` *handler* (extension or in-app) | — | **Absent**. No Intents extension target, no `INIntentsSupported`, no `UIApplicationDelegate` at all |

### Why each gap matters

1. **`INMediaUserContext`** is the declaration that registers the app with the media-suggestion engine as a media app with playable content (`subscriptionStatus`, `numberOfLibraryItems`). Without it, donations accumulate as generic shortcut history rather than media-app signal. This is the most likely reason a single KEXP launch qualifies and repeated WXYC launches do not.

2. **`INUpcomingMediaManager`** (`setSuggestedMediaIntents(_:)`) is the API purpose-built for this scenario: it hands iOS the concrete intents to offer when the user connects headphones or starts driving. Nothing is queued, so there is nothing for the system to offer even if it wanted to.

3. **No SiriKit handler.** A suggestion tile is dispatched as an `INPlayMediaIntent` — that is the type `setSuggestedMediaIntents(_:)` takes. The app's only SiriKit intake is `NSUserActivity` continuation (`AppLifecycleModifier.swift:144`), which requires a foreground launch.

   This gap is **SiriKit-specific, and narrower than it first looks.** The App Intents side is already background-capable: `PlayWXYC` ships `openAppWhenRun = false` and `supportedModes = [.background]` (`Shared/Intents/Sources/Intents/PlayWXYC.swift:20,42-43`), and `PlayWXYCAudio` adopts `.audio.playAudio` (the #450 fix). Whether iOS 26/27 bridges a dispatched `INPlayMediaIntent` onto an adopted audio `AppSchema` is not something this plan can determine from the source — and it is the whole question of whether gap 3 needs closing at all. See "Why not just the AppSchema" below.

### Secondary defects found while investigating

- The two donation sites disagree on media item identifier (`"Play WXYC"` vs `"WXYC"`) and on `resumePlayback` (`false` vs `true`). Same station, two identities — this splits whatever per-item learning the system is doing across two buckets. A *third* identity exists on the App Intents side: `LiveRadioStationEntity.id == "org.wxyc.live"` (`Shared/Intents/Sources/Intents/LiveRadioStationEntity.swift:38`).
- The launch-time donation fires on every cold start regardless of whether the user ever pressed play, which is not the pattern Apple's guidance describes (donate on real playback).
- The play-time donation passes `artwork: nil`. The launch-time one does not — `UIImage.placeholder` (`WXYC/iOS/NowPlayingInfoCenterManager.swift:163`) is the station background composited with the logo, i.e. already good tile artwork. The asymmetry is the defect, not the placeholder.

## End state

- One station identifier — `org.wxyc.live` — shared by the SiriKit media item and the App Intents entity.
- `INMediaUserContext` published on each launch.
- `INUpcomingMediaManager` seeded with the WXYC play intent, in `.onlyPredictSuggestedIntents` mode for `.radioStation`.
- An in-app `INPlayMediaIntent` handler that iOS can launch in the background — required for the iOS 18.6–26 install base regardless of what the observation shows.
- Existing Siri/Shortcuts/App Intents routing (`PlayWXYC`, `PlayWXYCAudio`) unchanged and regression-checked.

## Design

### Module placement

Three pieces, three different homes, dictated by the existing dependency graph:

| Piece | Home | Why |
|---|---|---|
| Station identifier constant | `Shared/Core` (`RadioStation`) | Must be visible to both `PlaybackCore` and `WXYCIntents`. `LiveRadioStationEntity` is `#if compiler(>=6.4)`-gated, so its literal cannot be the shared source. |
| Canonical intent builder | `Shared/Playback/Sources/PlaybackCore` | `Playback` (which owns `AudioPlayerController`), `AppServices`, and `WXYCIntents` all already depend on `PlaybackCore`, and `PlaybackCore` depends on `Core`. `Core` is upstream too, but it is a foundational package with no SiriKit surface — putting `import Intents` there would drag SiriKit into every consumer's build graph, the same argument that keeps `Analytics` out of `Caching`. |
| `MediaSuggestionService` | `Shared/AppServices` | Same module as the existing donation services (`SpotlightDonationService`, `ConcertSpotlightWindowObserver`). Consumes the builder; nothing in `Playback` needs to import it. Note this is a *module* precedent only — see "Ownership" below, where this service deliberately diverges. |
| `PlayMediaIntentHandler` (PR 2) | `Shared/Intents/Sources/Intents` | Sits next to `PlayWXYC`/`PlayWXYCAudio`, and `WXYCIntents` already depends on the full `Playback` product — so `IntentPlayback` is reachable as a same-module internal, with no new `public` surface on it. |

The obvious-looking placement — everything in `AppServices` — does not compile. `AppServices/Package.swift:10` declares a dependency on `Playback`, so `AudioPlayerController` importing `AppServices` would be a cycle. `AppServices` also imports only the `PlaybackCore` product, not `Playback`, so it cannot reach `AudioPlayerController` at all.

**Gating, and why it needs build verification.** The builder uses `#if canImport(Intents) && !os(macOS)`, matching the spelling of the existing `donatePlayIntent()` gate. `INUpcomingMediaManager` is `API_AVAILABLE(ios, watchos) API_UNAVAILABLE(macos, tvos)`, so `MediaSuggestionService` is gated `#if os(iOS) && !targetEnvironment(macCatalyst)` — the WXYC target sets `SUPPORTS_MACCATALYST = YES` (`project.pbxproj:1095`), and Catalyst inherits iOS availability, so a bare `#if os(iOS)` would compile *and run* this on the Mac where the suggestion surface does not exist.

The exposure is not only about *platforms* — it is about link graphs. The Request Share Extension imports `AppServices` (`ShareViewController.swift:11`), which links `PlaybackCore` but not `Playback` (`AppServices/Package.swift:24`), so putting SiriKit in `PlaybackCore` pulls `Intents.framework` into an extension that has none today. Impact is small — nothing in `project.pbxproj` sets `APPLICATION_EXTENSION_API_ONLY`, so there is no extension-unavailability compile risk — but the Share Extension scheme belongs in the verification block for that reason.

The real new *platform* exposure is **`PlaybackCore`, not `Core`.** `Core` receives only a `String` constant — no platform surface at all. But the existing `donatePlayIntent()` gate is not the precedent it looks like: `AudioPlayerController` lives in target `Playback`, which depends unconditionally on `MP3StreamerModule`/`HLSPlayerModule` ("iOS/macOS/tvOS only, not watchOS" — `Playback/Package.swift:44,58,72-81`), so that call site never compiles on watchOS today. `PlaybackCore` does. Putting the builder there compiles `INMediaItem` / `INPlayMediaIntent` / `INImage` for watchOS **for the first time in this repo.** Those APIs are available on watchOS 3.2–5.0, so the `WatchXYC` build should pass — but it is load-bearing verification, and CI builds iOS only (`.github/workflows/build-and-test.yml:103`), so a break here ships silently. The long platform-gating comments at `AppServices/Package.swift:30-55` exist because this repo has been burned by exactly this class of mistake.

### Canonical intent identity

```swift
identifier: RadioStation.WXYC.identifier   // "org.wxyc.live"
title: "WXYC 89.3 FM"
type: .radioStation
resumePlayback: false                      // a live stream cannot be resumed
suggestedInvocationPhrase: "Play WXYC"
artwork: INImage?                          // parameter, not baked in
```

`suggestedInvocationPhrase` is part of the builder, not an afterthought: `WXYCApp.swift:391` sets it today and routing that call site through a builder that omits it would silently drop the phrase. Neither existing test would catch that — `WXYCAppShortcutsTests.swift:90-101` asserts only intent type and artwork presence.

**The Shortcuts entry's title changes, visibly.** The launch-time donation currently uses `title: "Play WXYC"` (`WXYCApp.swift:379`); the canonical identity uses `"WXYC 89.3 FM"`. This is intentional — a media item's title should name the station, not an imperative, and it matches `LiveRadioStationEntity.title`. The invocation phrase, which is what the user actually says, stays `"Play WXYC"`.

Adopting `org.wxyc.live` — rather than `RadioStation.WXYC.name` — collapses all three identities onto the one already published to the media domain by `LiveRadioStationEntity`. `LiveRadioStationEntity.init()` is updated to read the new `RadioStation.WXYC.identifier` so the literal exists once; `PlayWXYCAudioTests.swift:36-37` asserts that value and must keep passing. Changing the SiriKit identifier discards whatever donation history exists under `"WXYC"` / `"Play WXYC"`, which is acceptable — that history is already split two ways and is demonstrably not producing suggestions.

`resumePlayback: false` is the semantically correct value for a continuous live stream; the current `true` at the play-time site is the one to change.

**Artwork is a caller-supplied parameter.** There are three call sites, and they do not all pass the same thing: the launch-time donation (`WXYCApp.makeSiriIntentInteraction()`) keeps passing the composited `UIImage.placeholder` on its existing `nonisolated` path, unchanged; `AudioPlayerController.donatePlayIntent()` and `MediaSuggestionService` both pass `nil`.

The only real station image is `UIImage(named: "logo.pdf")` (`NowPlayingInfoCenterManager.swift:170`), an app-target asset a package cannot resolve. More decisively: `MediaSuggestionService` is `@MainActor` and runs on the launch path, so passing `UIImage.placeholder` there would perform the CoreGraphics compositing on the main actor at launch — precisely the hang that `WXYCApp.swift:274-308` and `NowPlayingInfoCenterManager.swift:149-163` exist to prevent (#740). The suggestion tile falls back to the app icon, which is what most media apps show anyway.

### Media user context

```swift
let context = INMediaUserContext()
context.subscriptionStatus = .subscribed   // free stream; the user can play content
context.numberOfLibraryItems = 1           // one station
context.becomeCurrent()
```

`.subscribed` means "this user can play content," not "this user pays" — correct for a free stream. Re-published on every launch, since the context is not persistent.

### Upcoming media

```swift
INUpcomingMediaManager.shared.setSuggestedMediaIntents(NSOrderedSet(array: [intent]))
INUpcomingMediaManager.shared.setPredictionMode(.onlyPredictSuggestedIntents, for: .radioStation)
```

`.onlyPredictSuggestedIntents` stops iOS from trying to predict individual playcuts — WXYC has exactly one playable thing, and letting the system invent per-track suggestions from donation history would produce tiles that cannot be honored.

### Isolation

`MediaSuggestionService` is `@MainActor`: `becomeCurrent()` and `INUpcomingMediaManager.shared` are app-global system state, which this codebase already models as main-actor work (`HandoffActivityManager`'s `@MainActor CurrentActivityControlling`). Passing `nil` artwork keeps it cheap enough for the main actor — that is the reason the artwork decision above is load-bearing rather than cosmetic.

It gets its **own** `Task` in `WXYCApp.init()`, next to `Task { await appState.fetchConfiguration() }` (`WXYCApp.swift:91`) — *not* the `Task` inside `donateSiriIntent()`. That `Task` is deliberately off the main actor (`WXYCApp.swift:283-328`, #740); routing a `@MainActor` service through it would force exactly the hop that comment exists to prevent. `donateSiriIntent()` is not modified beyond swapping its builder call.

### Ownership

`SpotlightDonationService` and `ConcertSpotlightWindowObserver` are stored properties on `Singletonia` (`WXYC/iOS/Singletonia.swift:49,68`) because they hold state and are invoked repeatedly across the app's life. `MediaSuggestionService` is not like that: it registers once at launch and holds nothing afterward. So it stays ownerless — constructed and used inside its `Task`, never retained.

The consequence for docs: only the AppServices row (`docs/architecture.md:11`) needs updating. The Singletonia service list (`:34`) does **not**, because nothing lands there.

### Why not just the AppSchema

PR 2's top risk is that `INIntentsSupported` adds a second media-domain claimant next to the `.audio.playAudio` schema that fixed #450. The alternative is to add nothing on the SiriKit side and lean on the existing background-capable App Intents — but `setSuggestedMediaIntents(_:)` takes `INPlayMediaIntent`, so the tile is SiriKit-shaped by construction, and whether iOS bridges its dispatch onto an adopted audio schema is undocumented as far as this plan can establish.

That uncertainty was originally why the PRs were sequenced behind a blocking gate. It no longer is. The audio schema is `@available(iOS 27.0, *)`, the app's floor is iOS 18.6, and `.playAudioSchemaIntent` has one call site inside that gate — so for the whole 18.6–26 install base there is no in-place path at all, and PR 2 is required regardless of what any measurement shows. The observation below is worth running, but it refines scope on iOS 27 only; it does not decide whether PR 2 happens.

### Test seams

Mirror `HandoffActivityManager`'s existing protocol-plus-spy pattern rather than inventing a new one:

```swift
@MainActor public protocol MediaUserContextPublishing { func becomeCurrent(_ context: INMediaUserContext) }
@MainActor public protocol UpcomingMediaSuggesting {
    func setSuggestedMediaIntents(_ intents: NSOrderedSet)
    func setPredictionMode(_ mode: INUpcomingMediaPredictionMode, for type: INMediaItemType)
}
```

Both are `public`, matching module precedent (`SpotlightDonationService.swift:70`, `ConcertSpotlightWindowObserver.swift:82`). This is not stylistic: `MediaSuggestionService` is constructed from `WXYCApp.init()` in the app target, so it needs a `public init` — and a `public` initializer's default argument cannot reference an internal declaration. That is the same Swift rule PR 2 works around for `PlayMediaIntentHandler`; here the cheaper answer is to make the protocols public rather than split the initializer.

Real implementations forward to the singletons; tests inject spies, so the suite never mutates app-global system state. `WXYC/iOS/Tests/WXYCTests/HandoffActivityManagerTests.swift` is the model.

## Work breakdown

TDD throughout: failing test, then implementation, then refactor. Every new Swift file — sources, test files, and spy types alike — needs the standard header (`docs/file-headers.md`), enforced by `scripts/hooks/header-check.sh`.

**Ordering:** the `mac-seams-presentation` branch (live worktree at `.claude/worktrees/mac-seams-presentation`, 5 commits ahead of `origin/master`) modifies `WXYC/iOS/WXYCApp.swift` and `WXYC/iOS/AppLifecycleModifier.swift` — the two app-target files PR 1 and PR 2 both edit. Rebase PR 1 after it lands, or expect to resolve conflicts in `init()` and the continuation path.

File an issue for PR 1 and name its branch from it, per the repo's convention (`feat/22-accent-components`, `refactor/767-banner-typography`). **File PR 2's issue separately** — a single shared issue would be auto-closed by PR 1's `Closes #N` while PR 2 is still open.

### PR 1 — Unify station identity and declare media eligibility

Branch `feat/<issue>-media-suggestion-identity`, worktree `.claude/worktrees/<issue>-media-suggestion-identity`. Low risk, no new handler, no routing change.

1. **Failing test** in `CoreTests`: `RadioStation.WXYC.identifier == "org.wxyc.live"`. Add the property; update `LiveRadioStationEntity.init()` (`LiveRadioStationEntity.swift:38`) to read it, and add `import Core` to that file — it currently imports only `AppIntents` (`:25`). The import goes *inside* the `#if compiler(>=6.4)` gate, so a missed one fails only on a Swift 6.4 toolchain. Confirm `PlayWXYCAudioTests.swift:36-37` still passes.
2. **Failing test** in `Shared/Playback/Tests/PlaybackTests/MediaIntentBuilderTests.swift`, using `@testable import PlaybackCore` (the convention there — see `PlaybackSourceTests.swift`) and carrying the same `#if canImport(Intents) && !os(macOS)` gate as the builder: the builder produces one identity — assert identifier, title, `.radioStation`, `resumePlayback == false`, `suggestedInvocationPhrase`, and that a supplied `INImage` survives onto the media item while `nil` yields `nil`.
3. Add the builder to `PlaybackCore` under `#if canImport(Intents) && !os(macOS)`. Rewrite `WXYCApp.makeSiriIntentInteraction()` and `AudioPlayerController.donatePlayIntent()` to call it. `WXYCApp.swift:14-32` imports `Playback` but not `PlaybackCore`, so add that import — the app target already links it (`WXYC/iOS/PlaybackReason+App.swift:11`).
4. Update `WXYCAppShortcutsTests`: `buildsPlayMediaIntent` (`:90`) asserts only `intent is INPlayMediaIntent` and `mediaItemCarriesPlaceholderArtwork` (`:96`) asserts only `artwork != nil` — neither touches identity today, so both need new assertions added rather than "updated." Keep the artwork test and its #740 doc comment as-is; artwork at that site is unchanged. Confirm `WXYCAppDonationEscapesMainActorTests` (same file, below) still passes — it is the #740 regression guard.
5. **Failing test** in `Shared/AppServices/Tests/AppServicesTests/MediaSuggestionServiceTests.swift` — alongside `ConcertSpotlightWindowObserverTests.swift`, *not* in the app target where the cited `HandoffActivityManagerTests` pattern model lives, since the service ships in `AppServices`. Same `#if os(iOS) && !targetEnvironment(macCatalyst)` gate as the service. `register()` publishes an `INMediaUserContext` with `.subscribed` / `1`, seeds exactly one suggested intent — carrying `nil` artwork — in `.onlyPredictSuggestedIntents` mode, and captures its registration event: all three against spies, with `MockStructuredAnalytics` for the last.
6. Implement `MediaSuggestionService` in `AppServices` under `#if os(iOS) && !targetEnvironment(macCatalyst)`, and wrap the `WXYCApp.init()` call site in the **same** gate. `WXYCApp.swift` compiles for Mac Catalyst (`project.pbxproj:1095`), so an unguarded call would fail to resolve in exactly the Catalyst build the verification block runs.
7. **No new reason for tile taps — the signal already exists.** `PlaybackReason.siriIntent` has exactly one production call site in the repo: `AppLifecycleModifier.swift:145`, the `INPlayMediaIntent`-continuation branch itself. Voice requests land on `.playIntent` / `.playAudioSchemaIntent` instead, and `PlaybackStartedEvent` already captures `reason.rawValue` (`AudioPlayerController.swift:648`). So `"Siri intent"` in PostHog *is* the tile/continuation series today; only the derived `PlaybackSource.siri` collapses it with voice. Adding a reason here would orphan `.siriIntent` while it is still asserted at `PlaybackSourceTests.swift:47,91`.

   Do this instead: **add** a doc comment to `.siriIntent` (`PlaybackReason.swift:70` is a bare declaration — unlike its neighbors `.handoff` at `:71-74` and `.playAudioSchemaIntent` at `:86-88`, which carry one) saying plainly that it means a replayed `INPlayMediaIntent` continuation and nothing else. The name reads like a catch-all for voice, which is what made this look like a gap. Leave the `rawValue` alone — the existing PostHog series depends on it.
8. Update the AppServices row in `docs/architecture.md:11`. Do **not** touch the Singletonia list at `:34` — see "Ownership" above.
9. Leave the launch-time `NSUserActivity.becomeCurrent()` in `performDonation` untouched — it feeds Spotlight/prediction and is a separate, already-shipped concern.

### Observation (does not block PR 2)

Ship PR 1 and run the manual protocol below for at least three days. **This is a measurement, not a gate** — PR 2 is already known-required for every device below iOS 27 (see "Why not just the AppSchema"), so it can be built in parallel. What the observation refines is whether PR 2 also buys anything on iOS 27, and whether the eligibility declarations landed at all.

Three outcomes:

**The observation only asks a question on iOS 27, and it is a narrower question than it first appears.**

The in-place path runs through `PlayWXYCAudio`, which is `#if compiler(>=6.4)` + `@available(iOS 27.0, *)` (`PlayWXYCAudio.swift:19,23`), and `.playAudioSchemaIntent` has exactly one production call site — inside it (`:32`). So on iOS 18.6–26 there is no audio-schema intake at all: a tile cannot play in place, only foreground-launch. **PR 2 is therefore load-bearing for the entire pre-iOS-27 install base regardless of what is observed.** The app's minimum is iOS 18.6.

What the observation refines is narrower: whether PR 2 also buys anything *on iOS 27*. Run it on an iOS 27 device with an iOS-27-SDK build — a run on iOS 26 cannot observe the in-place outcome and would collapse it into "no tiles," an actively misleading reading.

Read **two** PostHog series on `PlaybackStartedEvent.reason`, against a launch-time baseline so a step change is attributable:

- `"Siri intent"` — the `INPlayMediaIntent` continuation, i.e. a tile that foreground-launched the app.
- `"PlayWXYCAudio intent"` — the audio schema, i.e. a tile iOS dispatched in place (this series also carries genuine voice requests, which is why the baseline matters).

Without both, the observation cannot tell "tile fired and played in place" from "no tile at all."

- **Tiles appear, and tapping one starts playback in place (iOS 27).** iOS is already servicing the dispatch through the audio schema on 27. PR 2 then buys nothing *on 27* — but still fixes 18.6–26, so it becomes a judgment call about whether foreground-launching older devices is acceptable, weighed against the #450 collision risk. This is the only outcome where declining PR 2 is defensible.
- **Tiles appear, but tapping one foreground-launches the app.** PR 2 is load-bearing on every OS version — a background-capable SiriKit handler is exactly the missing piece.
- **No tiles at all.** Check the registration event (below) first: it separates "registered, iOS declined" from "`register()` never ran or was gated out of this build." If registration fired and iOS still declined, `INIntentsSupported` is the next hypothesis — a system with nothing to dispatch to has no reason to offer a tile. Re-diagnose only if PR 2 also produces nothing.

**The observation needs a registration signal to be falsifiable.** Reading only `PlaybackStartedEvent.reason` cannot distinguish "iOS declined" from "the `#if os(iOS) && !targetEnvironment(macCatalyst)` gate excluded this build" or "`register()` never ran." So `MediaSuggestionService` takes `analytics: AnalyticsService = StructuredPostHogAnalytics.shared` — the module's existing one-shot-service pattern (`SpotlightDonationService.swift:124`, `ConcertSpotlightDonationService.swift:146`) — and captures an `@AnalyticsEvent` in `register()`. That event is the observation's baseline series.

### PR 2 — Background-capable `INPlayMediaIntent` handler

Branch `feat/<pr2-issue>-media-suggestion-handler`, worktree `.claude/worktrees/<pr2-issue>-media-suggestion-handler`, off its own issue. Required for iOS 18.6–26 regardless of the observation; can be built in parallel with PR 1 rather than after it.

No capability work is needed: `com.apple.developer.siri` is already granted in `WXYC/Entitlements/WXYC.entitlements:15`.

1. **Add a start seam, with an access-control split that actually compiles.** `IntentPlayback.startAndAwait(reason:timeout:)` (`IntentPlayback.swift:24-34`) hardcodes `AudioPlayerController.shared.prepareForPlayback()` and `.play(reason:)`; only `awaitPlaybackStart` takes an injectable closure. That is why the one existing intent-playback test (`WXYC/iOS/Tests/WXYCTests/PlayWXYCIntentTests.swift:20-25`) is `.tags(.e2e)` and disabled unless `RUN_E2E=1`.

   `PlayMediaIntentHandler` must be `public` (the app-target delegate returns it), but `IntentPlayback` is internal (`IntentPlayback.swift:20`) — and Swift forbids a `public` initializer's default argument from referencing an internal declaration. So: an **internal** seam initializer taking the `start:` closure, plus a separate `public init()` that forwards to it. The closure is spelled `{ await IntentPlayback.startAndAwait(reason: $0) }`, not a bare function reference — `startAndAwait` takes two parameters and won't match a one-parameter closure type.
2. **Failing test**: the handler returns `INPlayMediaIntentResponse(code: .success, userActivity: nil)` and starts playback with `PlaybackReason.mediaSuggestion`, against the injected start closure.
3. Declare `PlaybackReason.mediaSuggestion` in `PlaybackReason.swift`, alongside `.siriIntent` (`:70`) and `.playAudioSchemaIntent` (`:88`), and add it to the **existing** `// Siri / Shortcuts / App Intents` case group in `PlaybackSource.swift:143`. A declaration without a mapping degrades silently to `.unknown` — both halves are required. **Decide `.lockScreen` deliberately:** `PlaybackSource.lockScreen` (`:57-63`) is reserved for "a real distinguishing signal," and `lockScreenIsUnreachableToday` exists to force that question on every new reason. The tile is *not* that signal — it appears in the Home Screen suggestions row and CarPlay as well as the Lock Screen, so it cannot distinguish one surface from another. Map to `.siri` and record this reasoning in `.lockScreen`'s doc comment so the next person does not re-litigate it. That switch ends in `default: return .unknown`, so a missed mapping degrades silently; update **both** test sites — the `mapsToExpectedSource` arguments list (`PlaybackSourceTests.swift:47-51`) and the hand-maintained set in `lockScreenIsUnreachableToday` (`:84-93`).
4. Implement the handler in `Shared/Intents/Sources/Intents/PlayMediaIntentHandler.swift`, `public` so the app-target delegate can return it, under `#if os(iOS)`. That package declares iOS/watchOS/macOS and every platform-sensitive file in the directory is gated (`PlayWXYC.swift:45`); `INPlayMediaIntentHandling` is not uniformly available across them.
5. Add a minimal `AppDelegate` in `WXYC/iOS/`, wired via `@UIApplicationDelegateAdaptor`. **Constraint: it implements `application(_:handlerFor:)` and nothing else.** In particular it must not implement `application(_:configurationForConnecting:options:)` — that takes precedence over the `UIApplicationSceneManifest` at `Info.plist:86-111`, which is what wires `WXYC.CarPlaySceneDelegate`. New app-target file: follow the `project.pbxproj` playbook in `docs/project-structure.md` and validate with `xcodebuild -list`.
6. Add `INIntentsSupported` = `[INPlayMediaIntent]` to `WXYC/iOS/Assets/Info.plist`, and confirm it lands only there. There is no separate CarPlay plist to worry about — CarPlay is declared inside the app's own plist (`Info.plist:86-111`, `WXYC.CarPlaySceneDelegate` at `:100`) — and the Share Extension and NowPlayingWidget have wholly separate `INFOPLIST_FILE`s (`project.pbxproj:1006,1229`), so there is no inheritance to guard against. The real sibling to check is `WXYC/WXYC TV/WXYC-TV-Info.plist`.
7. Confirm `AppLifecycleModifier.swift:144`'s continuation path still works and does not double-start playback when the handler already did.
8. Docs, two files. **`docs/configuration.md`**: PR 2 introduces three things this repo has never had — an `AppDelegate`, a `UIApplicationDelegateAdaptor`, and `INIntentsSupported` — and that file is already where extension targets, entitlements, and Info.plist facts live. Record why the delegate exists and, critically, why it must never grow `application(_:configurationForConnecting:options:)`; that constraint currently lives only in this plan, which does not survive the merge. **`docs/architecture.md:18`**: the Intents row reads "App Intents (`WXYCIntents` product)", and PR 2 puts the repo's first SiriKit `INPlayMediaIntentHandling` conformer in that package — a different technology from App Intents, sitting in a row that currently claims otherwise.

Both PRs are well under the 1000-line target.

## Risks

**Siri routing regression (highest, PR 2 only).** #450 saw "Hey Siri, play WXYC" routed to Apple Music instead of WXYC's AppShortcut, fixed by adopting the iOS 27 audio `AppSchema`. Declaring `INIntentsSupported` adds a second media-domain claimant alongside it. **Do not ship PR 2 without re-testing "Hey Siri, play WXYC" on both iOS 26 and iOS 27 on device.** The observation gate exists partly so this risk is only taken when it buys something.

**CarPlay scene creation (PR 2).** Covered by the step-5 constraint above, but worth stating separately: an over-broad app delegate silently breaks CarPlay, and nothing in the test suite would catch it.

**Double-start (PR 2).** With both a handler and the `NSUserActivity` continuation live, a single suggestion tap could reach `AudioPlayerController.play` twice. `play(reason:)` is expected to be idempotent while already playing, but this needs an explicit test rather than an assumption.

**The payoff is heuristic and delayed.** Apple guarantees nothing about when or whether the system suggests an app. Expect a day or more of on-device learning before any tile appears — consistent with the KEXP observation. The work cannot be verified quickly, and a negative result the same afternoon proves nothing. This is why the observation gate is measured in days.

## Verification

**Automated, before every push:**

```bash
export TEST_RUNNER_WXYC_SKIP_KNOWN_FLAKES=1
scripts/test-affected.sh --full
```

Both PRs touch `Core`, `PlaybackCore`, `AppServices`, `WXYCIntents`, and `WXYC/**`, which forces the full plan anyway. The `TEST_RUNNER_` prefix is not optional and not cosmetic — without it `KeychainTokenStorageTests` and `DeviceFingerprintTests` fail on every local run, and the bare `WXYC_SKIP_KNOWN_FLAKES` spelling never reaches the simulator.

**Multi-platform builds** (CI covers iOS only, so these are the only guard on the new `#if` gates):

```bash
xcodebuild build -scheme WatchXYC -destination 'generic/platform=watchOS' -skipMacroValidation
xcodebuild build -scheme 'WXYC TV' -destination 'generic/platform=tvOS'   -skipMacroValidation
xcodebuild build -scheme WXYC      -destination 'generic/platform=macOS,variant=Mac Catalyst' -skipMacroValidation
xcodebuild build -scheme 'Request Share Extension' -destination 'generic/platform=iOS' -skipMacroValidation
```

The Share Extension build is not redundant with the app build: it is the target that newly gains `Intents.framework` through `AppServices` → `PlaybackCore`.

**Manual, on a real device — not the simulator.** Nothing in the suite can prove the suggestion appears:

1. Install, launch, press play once, background the app.
2. Confirm **Settings → Apps → Siri → WXYC** exposes the suggestion toggles (their presence is evidence the media-app declaration registered).
3. Confirm the Shortcuts app lists the WXYC media intent.
4. Connect Bluetooth headphones. Check the Home Screen Siri Suggestions row and the Lock Screen.
5. Repeat over at least three days — the engine needs repeated play-then-connect pairs. Record whether tiles appear, and if so whether tapping one foreground-launches. This is the observation gate.
6. Regression: "Hey Siri, play WXYC" still starts WXYC (both OS versions).
7. Regression (PR 2): CarPlay still connects and shows the WXYC now-playing template.
8. Regression (PR 2): tapping a tile starts playback without a foreground launch, exactly once.

## Open questions

- `numberOfLibraryItems`: `1` (the station) is the honest count of playable items. The app also has a LikedSongs store — if a larger number materially increases suggestion weight, that is worth measuring, but liked songs are not independently playable, so reporting them would be a misrepresentation. Proceeding with `1`.
- Whether to keep the launch-time `INInteraction.donate()` at all once `INUpcomingMediaManager` is seeding suggestions directly. Keeping it is the conservative choice for PR 1; dropping it (leaving only the play-gated donation at `AudioPlayerController.swift:651`) would improve signal quality. Deferred — it is a behavior change that deserves its own before/after observation.
- Closing the artwork gap would mean moving `logo.pdf` and the `UIImage.placeholder` compositing into a package, on a `nonisolated` path, so both `AudioPlayerController` and `MediaSuggestionService` could reach it without the #740 hazard. Out of scope; worth a follow-up ticket if app-icon fallback on the tile turns out to look wrong.
