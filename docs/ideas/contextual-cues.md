---
status: converted-to-tickets
source: brainstorm grounded in `https://developer.apple.com/documentation/AppIntents/providing-contextual-cues-to-apple-intelligence-and-siri`
captured: 2026-06-09
converted: 2026-07-08
epic: https://github.com/WXYC/wxyc-ios-64/issues/424
related: docs/ideas/spotlight-app-entities.md
---

# Contextual Cues for Apple Intelligence & Siri — Idea Backlog

> **Converted to tickets 2026-07-08.** Parent epic: [#424](https://github.com/WXYC/wxyc-ios-64/issues/424). Every backlog item below (CC-F1 through CC-Q2, including CC-F5) is now a sub-issue of #424 with cross-doc `blocked_by` edges to the spotlight-side entity work in [#423](https://github.com/WXYC/wxyc-ios-64/issues/423). File new ideas as sub-issues of #424, not as edits to this doc; this doc is kept as background context (rationale, glossary, references) for anyone reading the tickets cold.

This document captures opportunities to annotate WXYC's view layer and system integration points with `AppEntity` identifiers so that Apple Intelligence and Siri can reason about *what is currently on screen* during a conversation — answering "who is this?", "save this", "send this to Sarah" with the right entity already resolved. It is *not* yet a plan. It is the context a future planning pass needs in order to break the work into well-scoped projects and issues.

## TL;DR

Adopting the `appEntityIdentifier` / `appEntityUIElements` view annotations plus `MPNowPlayingInfoPropertyAppEntityIdentifiers` turns WXYC's existing now-playing surface into a contextually-addressable target for Siri. The biggest immediate wins are: (1) Siri can answer "who is this?" / "what label?" / "who's the DJ?" from the Lock Screen, CarPlay, AirPods, and the Apple Watch without any custom intent code, (2) Visual Intelligence and the on-screen-content path can resolve "this song" / "this artist" / "this show" to the right entity, and (3) the historical Flowsheet view becomes voice-addressable ("what was the third one?"). The work is downstream of the spotlight doc's foundation — entities have to exist before we can annotate views with them — but every other step is small, additive, and per-surface.

## Relationship to `spotlight-app-entities.md`

The two documents cover orthogonal halves of the same App Intents picture and share the entity types.

| | `spotlight-app-entities.md` (retrieval) | this document (real-time context) |
|---|---|---|
| Question it answers | "How does someone *find* a WXYC playcut they aren't looking at?" | "When someone is looking at a WXYC playcut, how does Siri know that's what 'this' means?" |
| Primary APIs | `IndexedEntity`, `EntityQuery`, `CSSearchableIndex.indexAppEntities`, `OpenIntent`, `AppShortcutsProvider` | `appEntityIdentifier(_:)`, `appEntityUIElements(_:)`, `AppEntityUIElement`, `AppEntityAnnotatable`, `MPNowPlayingInfoPropertyAppEntityIdentifiers`, `IntentValueRepresentation` |
| Shared prereq | Defines entities — `PlaycutEntity` in spotlight `F1`; the rest (`ShowEntity`, `ArtistEntity`, `ReleaseEntity`, `LabelEntity`, `DJEntity`) in spotlight `F5` | Consumes those entities. `CC-F1` only needs spotlight `F1`; `CC-F2` / `CC-F4` / `CC-C1` / `CC-C3` / `CC-C5` need spotlight `F5` |
| Donation model | Persistent, asynchronous, upserted into a system index | Ephemeral, synchronous, attached to a view or a now-playing-info dictionary |
| Where the user benefits | Spotlight, system search, Siri "find me…" | Siri conversational anaphora, Visual Intelligence, Lock Screen / CarPlay voice |

Do not duplicate work between the two. Where the spotlight doc owns a piece (entity declaration, schema choice, identifier strategy), this doc references it. Where this doc adds something the spotlight doc does not need (a new `StationEntity` for `PlaceDescriptor` bridging, an `IntentValueRepresentation` for `DJEntity`), it is called out explicitly.

## Current state (snapshot 2026-06-09)

### What we annotate today

Nothing. No view in the app currently carries an `appEntityIdentifier`, no `nowPlayingInfo` dictionary carries `MPNowPlayingInfoPropertyAppEntityIdentifiers`, no `UNMutableNotificationContent` carries an `appEntityIdentifier`, and no `AlarmConfiguration` carries an entity. The system has no on-device context for what WXYC's UI is showing at any given moment.

### Surfaces that exist to be annotated

| Surface | Location (verify exact path) | Why it matters |
|---|---|---|
| Now Playing view (iOS/iPad) | `WXYC/iOS/` somewhere under the playback flow | The single highest-value annotation site. Drives lock-screen Siri context indirectly via the same data the user sees in-app. |
| Playlist / Flowsheet view | likely `WXYC/iOS/` or a Playlist-package view | Per-row entity annotation makes "what was the song before this?" tractable. |
| `MPNowPlayingInfoCenter` updater | `WXYC/iOS/NowPlayingInfoCenterManager.swift` (single canonical write site; Playback only exposes a `NowPlayingInfoCenterProtocol` abstraction) | Drives Lock Screen, CarPlay, AirPods spatial-audio overlay, HomePod handoff. One field change reaches all of them. |
| Show schedule grid | not present today; would be built | Voice queries about upcoming shows are a natural fit. |
| Widget timeline | `Shared/AppServices/NowPlayingWidgetIntent.swift` and friends | Each timeline entry could carry an entity identifier. |
| Wallpaper background | `Shared/Wallpaper/` (private submodule → `WXYC/wallpaper-ios`; init with `git submodule update --init`) | Metal-backed generative shader background, not a per-playcut tile mosaic — `appEntityUIElements` does not apply; a single `appEntityIdentifier` on the SwiftUI container is what's viable. See CC-C4. |
| CarPlay scene | `WXYC/iOS/CarPlaySceneDelegate.swift` (scene delegate in the iOS app target, not a separate extension) | Voice-only environment; entity context is what makes the voice useful. |
| watchOS Now Playing view | the watchOS app target | Constrained UI, voice-friendly. |
| tvOS viewer | the tvOS app target | Lower priority; benefits inherited for free if entities exist. |
| Push notifications | wherever `UNMutableNotificationContent` is constructed | DJ-on-air / favorite-spinning notifications could carry the entity. |

### What does not exist yet

- No `AppEntity` conformances anywhere in the repo (see spotlight `F1`).
- No view-layer `appEntityIdentifier(_:)` or `appEntityUIElements(_:)` modifier usage.
- No `IntentValueRepresentation` bridges to `IntentPerson`, `PlaceDescriptor`, or `PersonNameComponents`.
- No `MPNowPlayingInfoPropertyAppEntityIdentifiers` attachment to the now-playing dictionary.
- No `AppEntityAnnotatable` adoption on notifications, alarms, or any other system type.
- No `StationEntity` (would be new; not covered by the spotlight doc).
- No show schedule grid view to annotate.
- No deep-link target for `OpenShow`, `OpenArtist`, `OpenDJ` (entities can be declared without these but conversational follow-ups stall without them).

### Data already shaped like entities

See the inventory in `docs/ideas/spotlight-app-entities.md` — the same `PlaycutEntity`, `ShowEntity`, `DJEntity`, `ArtistEntity`, `ReleaseEntity`, `LabelEntity` set applies. One addition unique to this document:

| Entity | Source | Notes |
|---|---|---|
| `StationEntity` | static — "WXYC 89.3 FM, Chapel Hill, NC" | Singleton. Candidate for `IntentValueRepresentation` ↔ `PlaceDescriptor`. Would also be the default entity for "WXYC" as an addressable proper noun in conversation. **iOS 27 unlocks a direct fit**: `AppSchema.audio.liveRadioStation` requires only `title` + optional `providerName` — same shape we'd build anyway. See CC-F4 and open question 3. |

### Hard constraints to design around

1. **Floor matches.** The view-annotation modifiers and `MPNowPlayingInfoPropertyAppEntityIdentifiers` are iOS 18.2 / macOS 15.2 / tvOS 18.2 / watchOS 11.2 / visionOS 2.2. WXYC's iOS 18.6 app-target floor is comfortably above. Note that `Shared/Intents` (which will host the new `AppEntity` types per spotlight `F1` / `F5`) is on iOS 18.4 — also above the cue floors. The watchOS / tvOS / Mac Catalyst floors need a quick audit before ticketing the per-platform parity items.
2. **`AppEntityAnnotatable` is opt-in by Apple.** Conformance is not extensible — adding `AppEntityAnnotatable` to a custom system type in your own code does nothing. Only the system types Apple has wired up (currently `MPNowPlayingInfo`, `UNMutableNotificationContent`, `AlarmManager.AlarmConfiguration`) deliver context. Plan around the closed set.
3. **`appEntityUIElements(_:)` closure is in the hot path.** The closure runs on visibility / selection changes, so it must not allocate aggressively or re-encode data. Same perf rules as `Canvas` content closures. Precompute the region → entity-identifier mapping at draw time, not inside the cue closure.
4. **Identifier stability.** Entities attached to long-lived surfaces (a notification, an alarm, a widget timeline entry) can outlive the app process. `PlaycutEntity.id` must be stable across launches — see spotlight doc open question 5.
5. **Schemas matter more here than for indexing.** The spotlight doc treats schema choice as a minor concern. For contextual cues it is the difference between Siri using its stock media-domain conversational behaviour and Siri treating the entity as opaque. Apply media schemas where they fit; do not roll a custom shape unless none does.
6. **AppShortcuts discovery breakage.** Commit `de99e7f3` reverted an `AppIntentsPackage` addition that broke `AppShortcuts` discovery. Until the root cause is understood, keep `AppEntity` declarations in a target the app target depends on directly. Re-introducing a separate package risks the same regression.
7. **Wallpaper is a private submodule with a Metal renderer.** `Shared/Wallpaper/` (`WXYC/wallpaper-ios`, private) is a Metal-backed generative shader background (`WallpaperRendererFactory` → `MetalWallpaperRenderer` / `MetalWallpaperView`), not a SwiftUI `Canvas` and not a mosaic of playcut artwork. Metal drawables are opaque to `appEntityUIElements`; CC-C4 therefore reduces to a single `.appEntityIdentifier(playcut)` on the SwiftUI container that hosts `WallpaperView`. Worktrees need `git submodule update --init` before the package resolves.
8. **CarPlay annotation flow is implicit, not explicit.** CarPlay does not expose its own view-annotation API; it consumes `MPNowPlayingInfoCenter`. Anything we want Siri-in-the-car to know must go through CC-F2.

## The Apple-side API surface we're adopting

- `appEntityIdentifier(_:)` SwiftUI view modifier — single-entity annotation.
- `appEntityUIElements(_:)` SwiftUI view modifier — multi-entity annotation for custom-drawn views, returning `[AppEntityUIElement]` in response to `context.requests` (`.visible(rect)` / `.selected`).
- `AppEntityUIElement` value type — identifier + bounds + state per element.
- `EntityIdentifier` — `EntityIdentifier(for: PlaycutEntity.self, identifier: id)`.
- `AppEntityAnnotatable` protocol — adoption is Apple-side only; we *consume* it on existing types.
- `MPNowPlayingInfoPropertyAppEntityIdentifiers` (`MediaPlayer`) — array of `EntityIdentifier` attached to the now-playing dictionary.
- `UNMutableNotificationContent.appEntityIdentifier` (via the mutable configuration object) — single entity per notification.
- `AlarmManager.AlarmConfiguration` entity field — for AlarmKit alarms.
- `IntentValueRepresentation` (in `Transferable`) — bidirectional bridge to `IntentPerson`, `PlaceDescriptor`, `PersonNameComponents`.
- `NSUserActivity.appEntityIdentifier` — backstop for OS versions below the iOS 18.2 floor. Not needed at our deployment target but worth knowing exists.
- UIKit/AppKit equivalents (`UIResponder.appEntityIdentifier`, `UIView.appEntityUIElementProvider`) — not expected to be used in this codebase given the SwiftUI policy in `docs/swiftui.md`, but noted for completeness.

## Annotation sites — a topological tour

Reading order matches how a listener actually encounters the app:

1. **Now Playing view** (root, persistent surface). One `appEntityIdentifier` for the playcut, or `appEntityUIElements` if multiple visible sub-areas (artwork, track info, show header, DJ chip) should be independently addressable.
2. **`MPNowPlayingInfoCenter` updater**. One write site, an array of `[playcut, show, dj, artist, release]` entity identifiers when known.
3. **Flowsheet / Playlist scrollback**. One annotation per row. Cheap; List provides bounds for free.
4. **Show schedule grid** (when built). One annotation per cell; `ShowEntity` + `DJEntity`.
5. **Wallpaper background** (private submodule, available). Single `appEntityIdentifier` on the SwiftUI container that hosts `WallpaperView` — the Metal drawable itself is opaque to `appEntityUIElements`.
6. **Widget timeline entries**. Entity identifier stored on the entry and projected into the rendered view.
7. **Push notifications**. `appEntityIdentifier` on the mutable notification content.
8. **AlarmKit alarms** (iOS 26 only). Entity on the `AlarmConfiguration`.
9. **CarPlay**. Implicit via `MPNowPlayingInfoCenter`; verify only.
10. **watchOS Now Playing**. Same annotation as iOS, on the watch view tree.

## Backlog

Each idea is sized **S/M/L/XL** for delivery scope and tagged with prerequisites. IDs use the `CC-` prefix to disambiguate from the spotlight doc's `F`/`C`/`Q` series.

### Foundation

#### CC-F1. Annotate the Now Playing view with `appEntityIdentifier(_:)`
- **Scope**: S.
- **What**: Wrap the Now Playing root view body with `.appEntityIdentifier(.init(for: PlaycutEntity.self, identifier: playcut.id))`. Re-evaluates on every playcut change (already a publisher in the codebase).
- **Why first**: It is the smallest possible diff that gets us a working litmus test for "is the cue layer alive?" — ask Siri "who is this?" with the Now Playing view in the foreground and verify it answers. Everything downstream depends on this loop being closed.
- **Prereqs**: spotlight `F1` (the `PlaycutEntity` type must exist).
- **Risks**: re-render churn — if the Now Playing view re-evaluates `.appEntityIdentifier` on every clock tick or playback-position update, the system may treat it as a continuous identity change. Bind the modifier to the playcut, not the position.
- **Out of scope**: schema choice (covered by CC-F4), multi-entity annotation for sub-areas (covered by a later upgrade to `appEntityUIElements`).

#### CC-F2. Attach the playcut + show + DJ entities to `MPNowPlayingInfoCenter`
- **Scope**: S.
- **What**: At the existing `MPNowPlayingInfoCenter.default().nowPlayingInfo` write site (`WXYC/iOS/NowPlayingInfoCenterManager.swift`), add the array key `MPNowPlayingInfoPropertyAppEntityIdentifiers` with `[playcut, show, dj]` (the ones currently known). The keys go in alongside the existing title/artist/artwork fields, not in place of them.
- **Why high priority**: this single write site feeds Lock Screen, CarPlay, AirPods Pro spatial-audio overlay, HomePod handoff, and the iPad mini-player simultaneously. One change, five surfaces.
- **Prereqs**: spotlight `F1` (`PlaycutEntity`) + spotlight `F5` (`ShowEntity`, `DJEntity`).
- **Risks**: `NowPlayingInfoCenterManager` writes from the main actor today; verify the entity identifier construction is `Sendable`-clean. `EntityIdentifier` is value-typed and should be fine.
- **Out of scope**: the `LabelEntity` (low marginal value at the now-playing seam — labels are an artist-page concern). The `ReleaseEntity` is borderline — include if cheap to derive.

#### CC-F3. Annotate Flowsheet rows with per-row entity identifiers
- **Scope**: S (List rows) to M (if the view uses a custom `Canvas`).
- **What**: For each visible row in the historical Flowsheet view, attach a `FlowsheetEntryEntity` (or `PlaycutEntity` if equivalent) identifier. If the view is a SwiftUI `List` / `LazyVStack`, this is one `.appEntityIdentifier(...)` per row. If it is a custom-drawn canvas, use `appEntityUIElements(_:)` with bounds.
- **Why**: unlocks "what was the song two before this?" and "the third song" disambiguation by visible context.
- **Prereqs**: CC-F1, spotlight `F1`. Optionally a `FlowsheetEntryEntity` type if we choose not to alias to `PlaycutEntity`.
- **Risks**: List rows can re-render on scroll; the `EntityIdentifier` must be derived from a stable id, not row index.

#### CC-F4. Apply matching `@AppEntity` audio schemas — gated on iOS 27
- **Scope**: S, **blocked on iOS 27 deployment floor**.
- **What**: Adopt the predefined `AppSchema.audio.*` schemas Apple ships in iOS 27. Mapping is unusually clean: `PlaycutEntity` → `.audio.song`, `ArtistEntity` → `.audio.artist`, `ReleaseEntity` → `.audio.album`, `StationEntity` → `.audio.liveRadioStation` (verbatim shape), `ShowEntity` → `.audio.radioShow`, per-airing show occurrences → `.audio.radioShowEpisode`. The Flowsheet is *not* a fit for `.audio.playlist` (which is for owned/curated lists with an `owner` and `createdByMe?` flag) — leave it as a custom entity. `LabelEntity` and `DJEntity` have no audio-domain analogue (DJ goes through CC-C1's `IntentPerson` bridge; Label stays custom). Each macro generates required properties and protocol conformance; CC-F4 is the reshaping work to make our entities satisfy those property requirements (see open question 3 for the full property list per schema).
- **Why**: a custom schema gets you the cue routing; a predefined schema gets you the cue routing *plus* Apple's audio-domain conversational behaviour (the article's promise) *plus* — for `.audio.liveRadioStation` specifically — Siri's stock understanding of "play this station". The fit is good enough that this is the right shape to head toward; the only question is when.
- **Prereqs**: spotlight `F1` (`PlaycutEntity`) + spotlight `F5` (other entities). **iOS 27 deployment floor** — all `.audio.*` schemas are introduced in iOS 27.0 / iPadOS 27.0 / macOS 27.0 / tvOS 27.0 / visionOS 27.0 / watchOS 27.0. WXYC's current iOS 18.6 floor cannot use them.
- **Why deferred**: at the iOS 18.6 floor, *no* media schema exists to apply (see open question 3). CC-F1 / CC-F2 / CC-F3 still deliver the cue layer without it; they just don't get the audio-domain conversational uplift. Ship those first; CC-F4 lands as a follow-on once the floor moves.
- **Adjacent opportunity unlocked at the same floor**: `.audio.playAudio` intent — implementing it would make "Hey Siri, play WXYC" natively resolve to the stream without any custom intent code. Consider grouping this with CC-F4 when the floor lifts.
- **Risks**: locked-in property names — `.audio.song` will require `artistName`, `composerName?`, `albumTitle?`, `artists: [ArtistEntity]`, `album: AlbumEntity?`, `composers: [ArtistEntity]`, `internationalStandardRecordingCode?`. Our Playcut data has the first three; `composers`, `album` entity link, and ISRC will be either nil-able or backfilled from library-metadata-lookup. Decide before adopting whether to round-trip ISRC, or leave it always-nil.

### User-facing capabilities

#### CC-C1. `DJEntity` ↔ `IntentPerson` bridge
- **Scope**: S.
- **What**: Conform `DJEntity` to `Transferable` with an `IntentValueRepresentation(exporting: importing:)` block converting between `DJEntity` and `IntentPerson` (identifier `.applicationDefined(dj.id)`, name `.displayName(dj.name)`, handle `nil` until a public-facing handle exists). Pattern follows the article's `ContactEntity` example verbatim.
- **Why**: DJs are people-shaped. Bridging to `IntentPerson` lets Apple Intelligence treat DJ names with the same conversational machinery it uses for contacts ("the DJ named Brian", "this person's other shows"). Cheap, on-brand.
- **Prereqs**: spotlight `F5` (`DJEntity` must exist).
- **Risks**: name uniqueness — DJs are commonly referred to by stage name only. The `.applicationDefined` identifier prevents collision with Contacts entries of the same first name.
- **Out of scope**: actual messaging affordance ("text DJ Brian"). The bridge enables the system to *understand*, not for us to *send*.

#### CC-C2. `StationEntity` → `PlaceDescriptor` bridge
- **Scope**: S.
- **What**: Introduce a singleton `StationEntity` (id `"wxyc"`, displayRepresentation "WXYC 89.3 FM"). Conform to `Transferable` with an `IntentValueRepresentation` to `PlaceDescriptor` (Chapel Hill, NC coordinates).
- **Why**: makes "WXYC" a first-class addressable proper noun in conversation, lets Maps surface "WXYC studios" as a real destination, and is the natural anchor for cross-app context ("share WXYC's stream").
- **Prereqs**: none beyond a place in the codebase to put it.
- **Risks**: none significant. The entity is a singleton; identifier collision is impossible.

#### CC-C3. Show schedule grid annotation
- **Scope**: M (mostly because the grid does not yet exist as a real view).
- **What**: When a weekly schedule view exists, annotate each cell with `appEntityIdentifier(.init(for: ShowEntity.self, identifier: show.id))` (and optionally `DJEntity` via `appEntityUIElements`).
- **Why**: enables "when is Brian's show?" / "set a reminder for the next 9 PM show" with on-screen disambiguation.
- **Prereqs**: spotlight `F5` (`ShowEntity` exists), plus a schedule view to annotate. The view itself is a larger UX project.
- **Risks**: dependent on the schedule view shipping. Defer until that lands.

#### CC-C4. Annotate the wallpaper container with the on-air playcut
- **Scope**: S.
- **What**: `Shared/Wallpaper/` (private submodule → `WXYC/wallpaper-ios`) is a Metal-backed generative shader background — `WallpaperView` composes `WallpaperRendererFactory.makeView(for: theme)`, and every theme renders through `MetalWallpaperRenderer` / `MetalWallpaperView` (see `Shared/Wallpaper/Sources/Wallpaper/Renderers/`). The Metal drawable is opaque to `appEntityUIElements`; there are no per-playcut sub-regions to address. What *is* addressable is the SwiftUI container that hosts the wallpaper. Attach `.appEntityIdentifier(.init(for: PlaycutEntity.self, identifier: playcut.id))` on `WallpaperView` (or the outermost wrapper the app inserts it under) so "who is this?" resolves the on-air playcut whenever the wallpaper is the top-most visible surface.
- **Why**: even a decorative background inherits conversational context this way. Highest yield in the two places the wallpaper spends the most time visible: iPad as a second-screen ambient view and any future tvOS ambient path.
- **Prereqs**: spotlight `F1` (`PlaycutEntity`). Read access to `WXYC/wallpaper-ios` (private).
- **Risks**: the modifier must be applied *outside* Metal's `MTKView` — attaching it inside would just annotate the SwiftUI wrapper around an opaque texture. Attach on `WallpaperView` or a container view that stays on the SwiftUI side of the boundary.
- **Out of scope**: per-region annotation. If a future wallpaper theme *does* render distinguishable per-playcut regions, revisit with `appEntityUIElements` as CC-C4a.

#### CC-C5. Notification entity attachment
- **Scope**: S.
- **What**: Wherever the app constructs a `UNMutableNotificationContent` for "DJ X is on air" / "your favourite artist is playing", set the `appEntityIdentifier` on the mutable configuration to the relevant `ShowEntity` / `PlaycutEntity` / `ArtistEntity`.
- **Why**: the swipe-action menu and Apple Intelligence-offered follow-ups become entity-aware. Siri can answer "what's this about?" without re-deriving from the notification title string.
- **Prereqs**: spotlight `F1` (`PlaycutEntity`) + spotlight `F5` (`ShowEntity`, `ArtistEntity` — only needed if the notification carries those rather than the playcut). Knowing whether the app actually sends push notifications today (audit) — if not, this is a per-notification add-on rather than a backfill.
- **Risks**: none significant; this is an additive field on a config we already build.

#### CC-C6. AlarmKit "wake me when this show starts" intent
- **Scope**: M.
- **What**: Define a new `AppIntent` "schedule a show alarm" that takes a `ShowEntity` parameter and creates an `AlarmManager.AlarmConfiguration` with the entity attached. Surface the affordance in the show schedule UI ("remind me next week") and as an App Shortcut.
- **Why**: a recurring radio show is the canonical use case for AlarmKit, and the entity attachment means "what's this alarm for?" / "cancel my WXYC alarm" resolve cleanly.
- **Prereqs**: spotlight `F5` (`ShowEntity`), CC-C3 (schedule view), iOS 26 floor on the surface (the rest of the app already targets iOS 26).
- **Risks**: AlarmKit deployment-floor mismatch on the watchOS target — audit before scoping.

#### CC-C7. Widget timeline entry entity field
- **Scope**: S.
- **What**: Add an `EntityIdentifier` field to the widget timeline entry, populate it from the current `PlaycutEntity`, and apply `.appEntityIdentifier(_:)` on the widget view body.
- **Why**: the widget participates in the Smart Stack's context-awareness story; Visual Intelligence sees it like any other annotated surface.
- **Prereqs**: spotlight `F1`. Awareness of the widget refresh budget noted in `docs/configuration.md` — the field is small and free to compute, no budget impact.
- **Risks**: serialization size — `EntityIdentifier` should round-trip through the widget extension boundary; verify in a prototype.

#### CC-C8. CarPlay verification pass
- **Scope**: S (mostly verification, possibly zero code).
- **What**: With CC-F2 landed, verify on a CarPlay-connected device that "Hey Siri, who is this?" resolves the on-air `PlaycutEntity` and reads the artist back. Document the loop for future CarPlay regressions.
- **Why**: CarPlay's voice-only context is where this work has the highest user benefit and is also the easiest regression to miss in normal QA.
- **Prereqs**: CC-F2, a CarPlay simulator or a car.
- **Risks**: simulator limitations — CarPlay simulator may not exercise the Siri context path. Real-device test plan required.

#### CC-C9. watchOS Now Playing annotation
- **Scope**: S.
- **What**: Mirror CC-F1 on the watch's Now Playing view (and its complications if they surface enough text for entity-style annotation to matter).
- **Why**: the Action Button on Apple Watch Ultra plus on-wrist Siri make watchOS the second-most-voice-driven surface after CarPlay.
- **Prereqs**: CC-F1, watchOS target audit (deployment floor must be at least 11.2).
- **Risks**: actor isolation differences between iOS and watchOS targets — keep the entity construction synchronous and free of cross-isolate hops.

#### CC-C10. tvOS parity
- **Scope**: S, deferable.
- **What**: Apply the same Now Playing annotation pattern on tvOS.
- **Why**: parity, plus enables Siri Remote voice queries about on-air content.
- **Prereqs**: CC-F1, tvOS target audit.
- **Risks**: low. Worth doing for parity, not worth prioritizing.

### Internal / QA capabilities

#### CC-Q1. Visual Intelligence smoke test on a real device
- **Scope**: S.
- **What**: Write down a short, repeatable smoke-test procedure for verifying that on-screen entity context resolves. Phrases to test: "who is this?", "what label?", "who's the DJ?", "save this", "what was the last song?". Capture the expected entity resolution for each.
- **Why**: contextual cues fail silently. Without a smoke test we will not notice when a regression strips an annotation. The cost is small; the cost of *not* having it grows linearly with the number of annotated surfaces.
- **Prereqs**: at least CC-F1, ideally CC-F2 and CC-F3.
- **Risks**: requires a device with Apple Intelligence enabled and Siri-context permissions granted; document the setup as part of the smoke test.

#### CC-Q2. Analytics for entity-driven invocations
- **Scope**: S.
- **What**: Following the post-PR #139 typed-event pattern, capture analytics for each invocation that lands through the cue path (e.g., `SiriContextResolved`, `OpenIntentFromCue`). Lets us see in PostHog whether the cue work is delivering listener value.
- **Prereqs**: CC-F1, the existing `AnalyticsService` abstraction.
- **Risks**: distinguishing "Siri invoked because of cue context" from "Siri invoked via App Shortcut" requires the calling path to pass through a marker — verify the intent-invocation surface exposes enough metadata.

## Sequencing (recommended)

```
spotlight F1 ──┬─ CC-F1 ─ CC-F3 ─ CC-Q1
               ├─ CC-C4 (wallpaper container)         ← unblocked: private submodule available
               ├─ CC-C7 (widget)                      ← cheap follow-on
               ├─ CC-C9 (watchOS)                     ← parity
               ├─ CC-C10 (tvOS)                       ← parity, deferable
               └─ CC-Q2 (analytics)                   ← after CC-F1

spotlight F5 ──┬─ CC-F2 ──────── CC-C8
               ├─ CC-F4 (schema audit, multi-entity)
               ├─ CC-C1 (DJ → IntentPerson)
               ├─ CC-C5 (notifications)               ← cheap follow-on
               ├─ CC-C3 (schedule grid)               ← needs schedule view
               └─ CC-C6 (AlarmKit)                    ← depends on CC-C3

(no spotlight dep) ── CC-C2 (Station → PlaceDescriptor)
```

A reasonable v1 ship is **CC-F1 + CC-F2 + CC-F4 + CC-C5 + CC-C7 + CC-C8 + CC-Q1** — same scope as before, but now gated on spotlight `F5` having landed (CC-F2/CC-F4/CC-C5 depend on it). That delivers "WXYC's Now Playing surface is contextually addressable everywhere `MPNowPlayingInfoCenter` reaches, the schema is right, the widget participates, notifications carry context, and we have a smoke test to keep it that way."

A reasonable v2 ship adds **CC-F3 + CC-C1 + CC-C2 + CC-C4 + CC-C9 + CC-Q2** — Flowsheet rows, system-type bridges, wallpaper container, watch parity, analytics. CC-C4 moves up from v3 now that the Wallpaper submodule is available and the correct shape (single `appEntityIdentifier` on the SwiftUI container) is scope-S.

A reasonable v3 ship is the conditional / dependent set: CC-C3 (when the schedule grid lands), CC-C6 (after CC-C3), CC-C10 (parity).

## Open questions for ticketing

1. ~~**Do we already write to `MPNowPlayingInfoCenter.nowPlayingInfo` in one place, or several?**~~ **Resolved**: single canonical write site at `WXYC/iOS/NowPlayingInfoCenterManager.swift`. CC-F2 can target that file directly.
2. **Is the historical Flowsheet a `List` / `LazyVStack` or a custom-drawn surface?** Affects whether CC-F3 is a one-line-per-row change or a `Canvas`-style `appEntityUIElements` integration.
3. ~~**Which media schemas does Apple actually ship in iOS 18.6?**~~ **Resolved (2026-06-10)**: *none*. Apple's `AssistantSchemas` namespace in iOS 18.x covers Books, Browser, Camera, Files, Journal, Mail, Photos, Presentation, Reader, Spreadsheet, System, VisualIntelligence, Whiteboard, WordProcessor — no audio/music/radio shapes at all. The audio domain ships as `AppSchema.audio.*` in **iOS 27.0 / iPadOS 27.0 / macOS 27.0 / tvOS 27.0 / visionOS 27.0 / watchOS 27.0** (currently beta). Concrete schemas, with the properties the macro will require: `.audio.song` (`title`, `artistName`, `composerName?`, `albumTitle?`, `artists: [ArtistEntity]`, `album: AlbumEntity?`, `composers: [ArtistEntity]`, `internationalStandardRecordingCode?`); `.audio.artist` (`name`); `.audio.album` (`title`, `artistName`, `artists: [ArtistEntity]`, `universalProductCode?`); `.audio.liveRadioStation` (`title`, `providerName?`) — **a direct one-to-one fit for `StationEntity`**; `.audio.radioShow` (`title`); `.audio.radioShowEpisode` (`title`, `showName?`, `releaseDate?`, `show: RadioShowEntity?`); `.audio.playlist` (`title`, `owner?`, `createdByMe?`, `curatedForMe?`); `.audio.songCollection` (`title?`). Plus intent schemas worth knowing: `.audio.playAudio`, `.audio.addToLibrary`, `.audio.addToPlaylist`, `.audio.createStation`, `.audio.recognizeAudio`, `.audio.updateAudioAffinity`, `.audio.warmupAudioQueue`. **Implication**: CC-F4 is a no-op at the current iOS 18.6 floor — there is no media schema to apply. The cue layer (CC-F1/F2/F3) still ships, just without schema conformance. CC-F4 becomes a real ticket only once the deployment floor lifts to iOS 27, which would also unlock a new candidate (`.audio.playAudio` adoption: "Hey Siri, play WXYC" without writing a custom intent).
4. **Does the show schedule view exist as a design or a prototype?** CC-C3 / CC-C6 depend on this. If not, decide whether to ship the view first (under a separate epic) or defer the schedule-annotated cue work.
5. ~~**What is the wallpaper feature's renderer architecture?**~~ **Resolved (2026-07-07)**: Metal-backed procedural shader background — `WallpaperView` → `WallpaperRendererFactory` → `MetalWallpaperRenderer` / `MetalWallpaperView`, driven by `ThemeConfiguration` + `ThemeManifest` themes (see `Shared/Wallpaper/Sources/Wallpaper/Renderers/`). Not a SwiftUI `Canvas`, and not a mosaic of playcut artwork tiles. Consequence for CC-C4: `appEntityUIElements` does not apply — the Metal drawable is opaque; a single `.appEntityIdentifier(playcut)` on the SwiftUI `WallpaperView` container is the right shape. Prior mischaracterization ("in flight", "artwork tiles in a Canvas") stemmed from the private `WXYC/wallpaper-ios` submodule not being installed when the doc was written.
6. **Identifier strategy** — same as spotlight doc question 5. Resolve there, consume here.
7. **AppShortcuts discovery breakage** — same as spotlight doc question 6. Resolve there, consume here. Affects where `@AppEntity` declarations may live.
8. **CarPlay simulator coverage** — verify CC-C8's verification loop is real-device-only before scoping the smoke test.
9. **AlarmKit deployment floors across iOS/watchOS targets** — verify before scoping CC-C6.
10. **Are there other system types we expect to gain `AppEntityAnnotatable` adoption in the next iOS release?** If yes (e.g., a future Photos-style attachment, a Reminders-style attachment), it changes whether we batch the integration work or do it surface-by-surface.

## Glossary (Apple article → WXYC)

| Article term | WXYC equivalent |
|---|---|
| `StickyNote` (canvas example) | Multi-area Now Playing (later refinement to CC-F1); custom-drawn Flowsheet if adopted (see CC-F3, open question 2). *Not* the wallpaper — see CC-C4. |
| `ContactEntity` ↔ `IntentPerson` example | `DJEntity` ↔ `IntentPerson` bridge (CC-C1) |
| `appEntityIdentifier(_:)` view modifier | Now Playing root, Flowsheet rows, Widget body, watchOS Now Playing |
| `appEntityUIElements(_:)` view modifier | Multi-area Now Playing (later refinement to CC-F1); Flowsheet if custom-drawn (see CC-F3, open question 2). Not the wallpaper — Metal drawable is opaque; CC-C4 uses `appEntityIdentifier` on the container instead. |
| `MPNowPlayingInfoPropertyAppEntityIdentifiers` | CC-F2 |
| `AppEntityAnnotatable` on `UNMutableNotificationContent` | CC-C5 |
| `AppEntityAnnotatable` on `AlarmConfiguration` | CC-C6 |
| `IntentValueRepresentation` → `PlaceDescriptor` | `StationEntity` (CC-C2) |
| `IntentValueRepresentation` → `IntentPerson` | `DJEntity` (CC-C1) |
| `NSUserActivity.appEntityIdentifier` backstop | Not needed at our iOS 18.6 floor |

## References

- Apple Developer doc: [Providing contextual cues to Apple Intelligence and Siri](https://developer.apple.com/documentation/AppIntents/providing-contextual-cues-to-apple-intelligence-and-siri)
- Companion idea doc: `docs/ideas/spotlight-app-entities.md`
- Reverted regression to understand before re-introducing any `AppIntentsPackage`: commit `de99e7f3`
- Repo touchpoints: `Shared/Intents/`, `Shared/AppServices/`, `Shared/Playback/`, `Shared/Playlist/`, `Shared/Wallpaper/` (private submodule → `WXYC/wallpaper-ios`), `WXYC/iOS/`
- Project conventions: `docs/swiftui.md` (SwiftUI policy), `docs/configuration.md` (widget refresh budget), `docs/architecture.md` (package layout)
