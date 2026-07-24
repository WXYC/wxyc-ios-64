---
status: converted-to-tickets
source: brainstorm grounded in `https://developer.apple.com/documentation/AppIntents/making-app-entities-available-in-spotlight`
captured: 2026-06-09
converted: 2026-07-08
epic: https://github.com/WXYC/wxyc-ios-64/issues/423
related: docs/ideas/contextual-cues.md
---

# Spotlight + App Entities — Idea Backlog

> **Converted to tickets 2026-07-08.** Parent epic: [#423](https://github.com/WXYC/wxyc-ios-64/issues/423). Every backlog item below is now a sub-issue of #423 — F5 is split into five per-entity tickets (`ShowEntity`, `ArtistEntity`, `ReleaseEntity`, `LabelEntity`, `DJEntity`) so downstream contextual-cue work in [#424](https://github.com/WXYC/wxyc-ios-64/issues/424) unblocks entity-by-entity. File new ideas as sub-issues of #423, not as edits to this doc; this doc is kept as background context (rationale, glossary, references) for anyone reading the tickets cold.

This document captures opportunities to expose WXYC's playlist graph to Spotlight, Siri, and Apple Intelligence via the `IndexedEntity` family of App Intents APIs introduced for iOS 18+. It is *not* yet a plan. It is the context a future planning pass needs in order to break the work into well-scoped projects and issues.

## TL;DR

Adopting `IndexedEntity` turns the existing `Playcut` + metadata graph into system-searchable, Siri-addressable content. The biggest immediate-value wins are: (1) listeners can ask "what was that song?" and get an answer from Spotlight/Siri without opening the app, (2) recent plays become a system entity that Quick Note, Lock Screen, and the Action Button can target, and (3) DJ-authored notes become semantically searchable through Apple Intelligence. The work is additive — none of the existing intents change — but it does require introducing the first `AppEntity` types in the codebase.

## Current state (snapshot 2026-06-09)

### What ships today

| Surface | Type | Module |
|---|---|---|
| `PlayWXYC` | `AudioPlaybackIntent`, discoverable, `ControlConfigurationIntent` on iOS | `Shared/Intents` |
| `PauseWXYC` | `AudioPlaybackIntent`, non-discoverable | `Shared/Intents` |
| `ToggleWXYC` | `SetValueIntent` + `AudioPlaybackIntent`, non-discoverable | `Shared/Intents` |
| `NowPlayingWidgetIntent` | `WidgetConfigurationIntent` for Smart Stack relevance | `Shared/AppServices` |
| `WhatsPlayingOnWXYC` | `AppIntent`, discoverable, returns `ReturnsValue<String> & ProvidesDialog & ShowsSnippetView` with a cached-artwork snippet view | `WXYC/iOS/Intents.swift:41` |
| `MakeARequest` | `AppIntent`, discoverable, takes a `request: String` parameter, dispatches via `RequestService` | `WXYC/iOS/Intents.swift:152` |
| `WXYCAppShortcuts` | `AppShortcutsProvider`, registers `WhatsPlayingOnWXYC`, `PlayWXYC`, `MakeARequest` with example phrases | `WXYC/iOS/Intents.swift:181` |
| `INPlayMediaIntent` handler | Legacy SiriKit fallback | `WXYC/iOS/AppLifecycleModifier.swift` |
| `wxyc://` URL scheme | Deep link, currently `play`-only | `WXYC/iOS/AppLifecycleModifier.swift` |
| `UIApplicationShortcutItem` | Home-screen quick action: "play" | `WXYC/iOS/AppLifecycleModifier.swift` |

### What we already donate

Three donation paths exist today. Each teaches a *different* system surface — and none of them is the `IndexedEntity` content-index path the article introduces. Knowing the distinction matters when scoping F2.

| Donation site | API | What it teaches | Touches Spotlight? |
|---|---|---|---|
| `WXYCApp.donateSiriIntent()` (`WXYC/iOS/WXYCApp.swift:269`, once at launch) | `INInteraction.donate()` (legacy SiriKit) **plus** `NSUserActivity(activityType: "org.wxyc.iphoneapp.play")` with `isEligibleForSearch = true` + `becomeCurrent()` | Siri / Lock Screen suggestions for "play the station" + a single Spotlight row for the play action | Yes — one row, for the action only |
| `AudioPlayerController.donatePlayIntent()` (`Shared/Playback/Sources/PlaybackAPI/AudioPlayerController.swift:629`, every play) | `INInteraction.donate()` (legacy SiriKit) | Behavioural learning so iOS surfaces the app based on listening patterns | No |
| `AddedSongToLibrary` AppIntent donation (`WXYC/iOS/Intents.swift:106`, from `PlaycutDetailView.swift:234`) | Modern `AppIntent.donate()` — discoverable=false, perform is a no-op | Shortcuts / Siri behavioural learning: "user added song X by artist Y to service Z" | No |

The closest existing thing to "Playcut in Spotlight" is the launch `NSUserActivity` — but it's a single action row, not a catalogue of plays. F2's `CSSearchableIndex(name:).indexAppEntities(...)` is a fourth mechanism: a *content* index, queryable by artist/title/keywords, one row per playcut. Genuinely new work, but the existing per-play donation in `AudioPlayerController.donatePlayIntent()` is the obvious co-location point — we already have a hook that fires when a play starts, and the article's recommendation is to donate the current entity at the same time.

### What does *not* exist yet

- No `AppEntity` conformances anywhere in the repo. (The existing `AddedSongToLibrary`, `WhatsPlayingOnWXYC`, and `MakeARequest` are `AppIntent`s, not `AppEntity`s.)
- No `EntityQuery` / `IndexedEntityQuery` implementations.
- No `OpenIntent` types — every existing intent uses `openAppWhenRun = false`.
- No `CSSearchableIndex` content indexing. The launch `NSUserActivity` lands a single action row in Spotlight, but there is no catalogue of playcuts, artists, shows, or releases.
- No favourites or play-history feature, so user-behaviour ranking signals are unavailable.
- `Shared/SemanticIndex/` is an empty package stub (May 2026), but the git history shows multiple reverted integration attempts (commits `e129bd8e` / `c2901254` — "Add WXYC Recommends feature with semantic-index integration"; `80b8043e` / `1bf46c50` — "Clean up SemanticIndex package from review feedback"; `df2cb2a0` — "Decode semantic-index search and neighbors response wrappers"). For anyone scoping C3, the prior revert *reasons* are load-bearing context; re-read those PR threads before re-attempting.

### Data already shaped like entities

- **`Playcut`** (`Shared/Playlist/Sources/Playlist/PlaylistEntry.swift`) — the obvious primary entity. Already carries `artworkURL`, `discogsURL`, `releaseYear`, `spotifyURL`, `appleMusicURL`, `youtubeMusicURL`, `bandcampURL`, `soundcloudURL`, `artistBio`, `artistWikipediaURL`, `rotation: Bool`. `UInt64` `id` is naturally globally unique.
- **`ShowMarker`** — `isStart`, `djName`, `message`. The day's show grid is reconstructible from start/end markers.
- **`PlaycutMetadata` / `ArtistMetadata` / `AlbumMetadata` / `StreamingLinks`** (`Shared/Metadata/`) — richer side-loaded data, including Discogs genres, styles, full release date.
- **`NowPlayingItem`** — `Playcut` + fetched `Image` artwork.
- **`FlowsheetEntry`** (raw v2 wire model, internal) — `metadata_status` lifecycle field is interesting: tells us whether server-side enrichment is in-progress, complete, or unknown. This is the right trigger for deferred re-donation.

### Hard constraints to design around

1. **Client sees only the last 50 entries** via `wxyc.info/playlists/recentEntries?v=2&n=50`. No historical archive endpoint is consumed today. Without a new backend endpoint, the Spotlight index for `PlaycutEntity` grows accretively — only what background refresh has seen since first launch. Multi-year search requires backend work first.
2. **`NowPlayingService` is the canonical fan-out point** for "current playcut + artwork." Donation should hang off the same stream so we don't refetch.
3. **Rotation tracks have longer artwork TTL** (`Playcut.rotation`). Useful as a priority hint.
4. **No favourites yet.** Personal-relevance ranking is limited to recency + rotation + (eventually) listener behaviour.
5. **iOS 18.4 minimum on `Shared/Intents`; iOS 18.6 on the app target.** `IndexedEntity` requires iOS 18 / macOS 15 — both floors satisfy it. The package an entity lives in determines the API ceiling for that entity, not the app target. Putting `PlaycutEntity` in `Shared/Intents` (alongside `PlayWXYC` etc.) keeps the package boundary clean; if any future entity needs an iOS 18.4+ API, the package floor would need a bump.
6. **`@DeferredProperty` is resolved at indexing time.** Anything that hits the network during property access will stall the indexer. Discogs/Wikipedia lookups must be materialized into the Playcut row *before* donation.
7. **Spotlight's default index must not be used in production** — per Apple's doc. We need named indexes for every entity type.

## The Apple-side API surface we're adopting

- `IndexedEntity` protocol — extends an existing `AppEntity`. All requirements have defaults.
- `@Property` / `@ComputedProperty` / `@DeferredProperty` with `indexingKey:` (key path into `CSSearchableItemAttributeSet`) or `customIndexingKey: CSCustomAttributeKey`.
- `var attributeSet: CSSearchableItemAttributeSet { get }` — escape hatch for non-wrapped fields (latitude/longitude, `supportsNavigation`, audio attrs). Loses to wrapped property keys on collision; loses to `displayRepresentation` for title/subtitle/image.
- `CSSearchableIndex(name:).indexAppEntities(_:priority:)` — direct donation, upsert by `AppEntity.id`.
- `CSSearchableItemAttributeSet.associateAppEntity(_:priority:)` — bridge if we ever wire up the `CSSearchableItem` path alongside.
- `IndexedEntityQuery` — `reindexEntities(for:indexDescription:)` and `reindexAllEntities(indexDescription:)` so Spotlight can ask us to rebuild.
- `OpenIntent` — per entity, deep-links the Spotlight hit into the app.
- `ShowInAppSearchResultsIntent` — for queries with >10 hits, hands the query to our in-app search UI.

## Proposed entity inventory

| Entity | Source | Index name | Notes |
|---|---|---|---|
| `PlaycutEntity` | `Playcut` | `wxyc.playcuts` | Atomic unit. Accretive index. Use `id`, `chronOrderID`, `timeCreated`. |
| `ShowEntity` | derived from `ShowMarker` pairs + DJ data | `wxyc.shows` | A single airing of a show; identifier is `start chronOrderID` or backend show id. |
| `DJEntity` | derived from `ShowMarker.djName` (or future backend) | `wxyc.djs` | Tiny set, slow-changing. |
| `ArtistEntity` | derived from `Playcut.artistName` dedup | `wxyc.artists` | Deduplicates plays. Cheap, high re-use. |
| `ReleaseEntity` | derived from `Playcut` artist+release key | `wxyc.releases` | Album-level rollup. |
| `LabelEntity` | derived from `Playcut.labelName` | `wxyc.labels` | NC/indie label discovery axis. |

Out of scope for v1: `GenreEntity`, `TagEntity`, `LiveStreamEntity` (the stream itself doesn't need to be a Spotlight row — `PlayWXYC` already covers that).

## Indexing strategy

- **Named indexes** per entity kind so we can evict, version, and prioritize independently.
- **Donation triggers**:
  - On background refresh (we already log `Background refresh completed`) — diff against last donation watermark; donate delta.
  - When server-side metadata enrichment lands for a previously-donated playcut (`metadata_status` transitions to a terminal state) — re-donate that single row; `indexAppEntities` upserts on identifier.
  - On `NowPlayingService` tick — donate current playcut immediately with elevated priority.
- **Priority knobs** (no user behaviour yet):
  - `rotation == true` → +5 (station library tracks)
  - `airedAt` within last 24h → +3 (recency)
  - `releaseYear` within current year → +1 (newness)
  - Defaults to 1.
- **Reindex policy**: `reindexAllEntities` rebuilds the last 90 days + all rotation tracks we've ever seen. `reindexEntities(for:)` fetches single rows from cache by id.

## Backlog

Each idea is sized **S/M/L/XL** for delivery scope and tagged with prerequisites. "Foundation" must land before any user-facing idea.

### Foundation

#### F1. Introduce the first `AppEntity` type and the supporting query/intent
- **Scope**: M.
- **What**: Create `PlaycutEntity: AppEntity, IndexedEntity` plus `PlaycutEntityQuery: EntityQuery, IndexedEntityQuery` and `OpenPlaycut: OpenIntent`. Wire the `wxyc://` scheme to accept playcut IDs. Add the type to `Shared/Intents` (alongside the existing `PlayWXYC` etc.) so the package's iOS 18.4 floor applies and `WXYCAppShortcuts` can reach it without a new dependency.
- **Why first**: Every user-facing idea below depends on at least `PlaycutEntity` existing. Doing only `PlaycutEntity` first keeps the first PR scoped — supporting entity types (`ShowEntity`, `ArtistEntity`, `DJEntity`, `ReleaseEntity`, `LabelEntity`) follow in F5; per-kind donation pipelines and views follow in C5/C6.
- **Risks**: Identifier typing — `AppEntity.ID` is per-type, so `PlaycutEntity.ID = UInt64` and `ReleaseEntity.ID = UInt64` are distinct Swift types and cannot collide at the type level. Collision is only a concern if multiple entity kinds share a single `CSSearchableIndex(name:)`, which we deliberately avoid via named-per-kind indexes. Even so, defensive typed wrappers (e.g., `struct PlaycutID: Hashable, Sendable { let value: UInt64 }`) make future refactors safer; commit to one approach before F5 so all entities follow it.
- **Out of scope**: `CSSearchableIndex.indexAppEntities` content-index donation (that's F2). This PR just wires up the type so Siri/Shortcuts can refer to a playcut. The existing behavioural donations (`INInteraction.donate()` from `WXYCApp` and `AudioPlayerController`, `AppIntent.donate()` from `PlaycutDetailView`) are unaffected and remain in place.

#### F2. Donation pipeline anchored on `NowPlayingService`
- **Scope**: M.
- **What**: A new `SpotlightDonationService` (likely in `AppServices`) that subscribes to `NowPlayingService` and, on each tick + on background refresh completion, donates the current and recent playcuts to `CSSearchableIndex(name: "wxyc.playcuts")`. Tracks a "last donated chronOrderID" watermark in `DefaultsStorage`.
- **Relationship to existing donations**: this is the *fourth* donation mechanism, complementary to the three already in place. The existing `AudioPlayerController.donatePlayIntent()` is the natural co-location point — when a play starts, we already donate an `INPlayMediaIntent`; we can also call `indexAppEntities` with the current `PlaycutEntity` from the same callsite. Do not remove the existing donations — they teach different system surfaces (Siri suggestions, Shortcuts learning) that the content index does not replace.
- **Prereqs**: F1.
- **Risks**: Background-refresh budget — we already have a tight budget per `docs/configuration.md`; the donation work must be bounded (≤50 rows per refresh).
- **Privacy**: All donated content is public radio metadata. No listener PII in the index.

#### F3. `IndexedEntityQuery` reindex handlers — shipped ([#427](https://github.com/WXYC/wxyc-ios-64/issues/427))
- **Scope**: S.
- **What**: `PlaycutEntityQuery` adopts `IndexedEntityQuery` (new in iOS 27; gated `#if compiler(>=6.4)` in its own file, `PlaycutEntityQuery+IndexedEntityQuery.swift`, since the API isn't in the stable Xcode 26.5/26.6 SDK). Both handlers **return `Void`** — per Apple's docs, the implementation fetches the entities and *donates them again* rather than returning a value:
  ```swift
  func reindexEntities(for identifiers: [PlaycutID], indexDescription: CSSearchableIndexDescription) async throws
  func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws
  ```
  `CSSearchableIndexDescription` is an `NSObject` subclass exposing only a nullable `protectionClass` — there is no index name/identity on it to dispatch against, so both handlers donate straight to the one named `wxyc.playcuts` index via a small `PlaycutReindexer` seam (`donate(_ entities: [PlaycutEntity]) async throws`), regardless of what `indexDescription` carries. `reindexEntities(for:)` sources rows from `PlaycutHistoryStore.playcuts(ids:)` ([#465](https://github.com/WXYC/wxyc-ios-64/issues/465), not `CacheCoordinator.Playlist` as originally scoped here — that store didn't exist yet when this idea was written); ids the store doesn't have are omitted, not an error. `reindexAllEntities` donates `PlaycutHistoryStore.allIndexable()` (the last ~90 days + the durable rotation set) in `SpotlightDonationService.batchLimit`-sized (50) chunks. Both `PlaycutHistoryStore` and the reindexer seam are requested via `@Dependency` (`AppDependencyManager`), registered in `Singletonia.init()` before any intent/query can run.
- **Prereqs**: F1, F2, F3 prerequisite `PlaycutHistoryStore` ([#465](https://github.com/WXYC/wxyc-ios-64/issues/465)).

#### F4. Extend `WXYCAppShortcuts` with the new `OpenIntent` types
- **Scope**: S.
- **What**: Add entries to the existing `WXYCAppShortcuts: AppShortcutsProvider` (`WXYC/iOS/Intents.swift:181`) for `OpenPlaycut` (and later other `OpenIntent` variants such as `OpenShow`, `OpenArtist`) with example phrases. The provider already registers `WhatsPlayingOnWXYC`, `PlayWXYC`, and `MakeARequest` — F4 is additive.
- **Note**: Commit `de99e7f3` reverted an `AppIntentsPackage` addition that broke AppShortcuts discovery. The current implementation keeps `WXYCAppShortcuts` in the main app target deliberately; whoever picks this up should understand the revert before re-introducing any separate package for entity/intent declarations.

#### F5. Introduce the supporting entity types
- **Scope**: M.
- **What**: Declare bare `AppEntity` (and `IndexedEntity` where applicable) types for `ShowEntity`, `ArtistEntity`, `DJEntity`, `ReleaseEntity`, `LabelEntity`. Each gets a minimal `displayRepresentation` plus a minimal `EntityQuery` implementation sourced from the playcut cache (`CacheCoordinator.Playlist`). Does *not* set up per-kind donation pipelines, `OpenIntent`s, or new in-app views — those follow in C5 (`ShowEntity`), C6 (`ArtistEntity`), etc.
- **Why this is its own ticket**: `docs/ideas/contextual-cues.md` depends on these types existing — annotating views, attaching to `MPNowPlayingInfoCenter` — well before the donation/index/view work in C5/C6 lands. Splitting the type declarations from the index/view work keeps both backlogs unblocked.
- **Prereqs**: F1 (the typed-ID strategy decided there applies here).
- **Risks**: Dedup keys for derived entities (`ArtistEntity` from `Playcut.artistName`, `LabelEntity` from `Playcut.labelName`) — strings vary across plays. `Metadata`'s `DiscogsEntityResolver` already does some normalization; consume that rather than inventing a new one.

#### C1. "What was that song?" Spotlight lookup
- **Scope**: S (assuming F1+F2).
- **What**: With `Playcut.artist`, `Playcut.songTitle`, `Playcut.releaseTitle` indexed under `\.artist`, `\.title`, `\.album` keys, Spotlight surfaces "WXYC played this" results. `OpenPlaycut` deep-links to the in-app row.
- **Payoff**: Highest listener-delight value for the lowest incremental code. The full Playlist view should scroll to the matching entry.
- **Prereqs**: F1, F2, F4. Requires a destination view in the app — confirm what `OpenPlaycut` opens to (the timeline scrolled to that point, or a dedicated detail view).

#### C2. Album-art-as-Spotlight-thumbnail
- **Scope**: S.
- **What**: Set `displayRepresentation.image` from `Playcut.artworkURL` (already pre-fetched by `NowPlayingService` for recent rows). Spotlight uses the image directly in result rows.
- **Prereqs**: F1.
- **Risks**: `displayRepresentation` is synchronous; we must use a cached artwork path, not `MultisourceArtworkService.fetchArtwork(for:)` at access time. Probably means passing the cached `CGImage` or local file URL into the entity at construction time.
- **Existing pattern**: `WhatsPlayingOnWXYC.NowPlayingView` (`WXYC/iOS/Intents.swift:75`) already renders a cached `UIImage` from `NowPlayingItem.artwork` inside a Siri snippet — the same image cache should feed C2's `displayRepresentation`.

#### C3. Semantic search over DJ-authored content
- **Scope**: M (once `contentDescription` is filled).
- **What**: Map `Playcut.artistBio` (when present) and any DJ-authored notes onto `\.contentDescription` and `\.keywords` on `PlaycutEntity`. Apple Intelligence does the semantic search work for free.
- **Open question**: We don't currently store DJ-authored prose per playcut on the client — `ShowMarker.message` is the closest analog. If we want DJ notes in the index, we need a backend field or a derived signal (the artist bio is a fine first cut).
- **Payoff**: Queries like "krautrock from last week" or "long ambient tracks DJ Jake played" become tractable without any in-app NLP.

#### C4. Upgrade "what's playing on WXYC?" to return a `PlaycutEntity`
- **Scope**: S.
- **What**: `WhatsPlayingOnWXYC` (`WXYC/iOS/Intents.swift:41`) already ships — discoverable, returns `ReturnsValue<String> & ProvidesDialog & ShowsSnippetView`, registered in `WXYCAppShortcuts` with the phrase "What's playing on \(.applicationName)?". Upgrade its return type from `String` to `PlaycutEntity` so conversational follow-ups ("who's the artist?", "save this") resolve against the entity instead of re-parsing the dialog string. Add additional example phrases ("what was the last song on WXYC?") to the existing shortcut registration.
- **Prereqs**: F1, F4.
- **Risks**: Existing intent already pulls the current playcut from `AppIntentServices.nowPlayingService()` via an `AsyncIterator` — the actor-isolation path is already proven, so the upgrade is mechanical. Watch the legacy `String` return-type consumers (Shortcuts users who chained the string output) — if any exist in the wild, document the breakage.

#### C5. `ShowEntity` donation + "open last night's Backseat Mafia"
- **Scope**: L.
- **What**: Extend `ShowEntity` (declared in F5) with a real donation pipeline against `CSSearchableIndex(name: "wxyc.shows")`, an `OpenShow: OpenIntent`, and a per-show detail view. Each show airing is a separate entity with a tracklist; identifier is `start chronOrderID` or backend show id.
- **Prereqs**: F1, F2, F5, plus a new in-app "show detail" view. Probably needs a backend `/shows/{id}` endpoint to be useful beyond what we have in the 50-entry window.
- **Risks**: This is the largest user-facing capability. Most of the cost is the show-detail view, not the entity wiring.

#### C6. `ArtistEntity` donation + "show me what WXYC has played by Stereolab"
- **Scope**: M.
- **What**: Extend `ArtistEntity` (declared in F5) with the donation pipeline against `CSSearchableIndex(name: "wxyc.artists")` and a richer `EntityQuery` that backs into the playcut cache: "all playcuts where `artistName == self.name`." Indexed with `\.artist` plus `customIndexingKey` for the count of plays.
- **Prereqs**: F1, F2, F5.
- **Risks**: Dedup key — artist name strings vary ("Stereolab" vs "Stereolab feat. ..."). Need a normalization function shared with F5's minimal query. The `Metadata` package already does some of this work via `DiscogsEntityResolver`.

#### C7. `ShowInAppSearchResultsIntent` for prolific artists
- **Scope**: S.
- **What**: When a Spotlight search yields >10 hits (e.g., "Pavement"), the system hands the query to our `ShowInAppSearchResults` intent, which opens the app's archive search UI with the query preserved.
- **Prereqs**: F1, plus an in-app search UI capable of taking an external query. The current app does not appear to have a unified search view — this may need to be built. Worth confirming before scoping.

#### C8. Quick Note / Lock Screen / Action Button targeting
- **Scope**: S (mostly free once entities exist).
- **What**: With `PlaycutEntity` as a registered system entity, iOS Quick Note can attach a playcut to a note, Lock Screen Smart Stack can surface a "recent play" tile, and the Action Button can target an `OpenPlaycut` shortcut.
- **Prereqs**: F1, F4. Most of this is "free" once entities + `AppShortcutsProvider` exist; the work is verifying each surface and writing example shortcuts.

#### C9. Geographic affordances for local NC artists
- **Scope**: M.
- **What**: For artists with a known origin (Chapel Hill, Carrboro, Durham, etc.), set `latitude` / `longitude` / `supportsNavigation` on the `attributeSet`. Maps suggestions can then surface "venues / artist origins from your library."
- **Prereqs**: F1, F5 (`ArtistEntity` is where lat/lon hangs), plus a data source for artist origins. Discogs has some location data; verify what `Metadata` already exposes. May be deferable until a server-side artist-origin field exists.

#### C10. Re-donate on metadata enrichment
- **Scope**: S.
- **What**: When `FlowsheetEntry.metadata_status` transitions to a terminal "enriched" state for a previously-donated playcut, re-donate the row so newly available `artworkURL` / `discogsURL` / `releaseYear` make it into the index. Free upsert via `indexAppEntities`.
- **Prereqs**: F1, F2. Requires hooking into wherever `PlaylistService` observes status transitions today.

### Internal / QA capabilities

#### Q1. Internal-build-only "missing-artwork" entity
- **Scope**: S.
- **What**: In `DEBUG`/`TEST_FLIGHT` builds, index playcuts that failed Discogs/MusicBrainz lookup as a special `MissingMetadataEntity`. DJs can find them right from the home screen for triage.
- **Prereqs**: F1, F2. Behind a build-time gate so production indexes stay clean.

#### Q2. Donation analytics
- **Scope**: S.
- **What**: Following the post-PR #139 pattern, capture `SpotlightDonated`, `SpotlightDonationFailed`, `SpotlightReindexRequested` typed events through `AnalyticsService`. Lets us see in PostHog whether the index is being kept warm.
- **Prereqs**: F2.

## Sequencing (recommended)

```
F1 → F2 → F3 → F4 → F5
                  ↘
                   C1 ─ C2 ─ C4 ─ C8   (cheap, high-payoff)
                   C10                 (auto-correctness)
                   C6                  (artist axis; needs F5)
                   C3                  (semantic, depends on note data)
                   C5, C7              (need new in-app views; C5 needs F5)
                   C9                  (needs artist-origin data + F5)
                   Q1, Q2              (internal, any time after F2)
```

A reasonable v1 ship is **F1 + F2 + F3 + F4 + C1 + C2 + C8 + C10** — that delivers "WXYC plays show up in Spotlight with album art, are addressable from Quick Note / Lock Screen / Action Button, and stay correct as metadata enriches" with no new in-app views. C8 rides for free since all its prereqs (F1, F4) are already in v1. F5 is *not* in v1 — supporting entity types only become load-bearing once C5/C6 ship, or once `docs/ideas/contextual-cues.md` work starts.

## Open questions for ticketing

1. **Does `OpenPlaycut` scroll the existing Playlist view to that row, or open a dedicated playcut detail view?** Affects scope of F1.
2. **Is the in-app archive search a real surface or does it need to be built?** Affects scope of C7.
3. **What's the backend story for historical archive queries?** Without one, `PlaycutEntity` indexing only covers what background-refresh has seen since install. Worth a conversation with backend before sizing the "search all WXYC plays" capabilities.
4. **DJ-authored notes per playcut — do they exist server-side, and if not, is there appetite to add them?** This is the gate on C3's semantic-search payoff.
5. **Identifier strategy.** `Playcut.id` is `UInt64` and `AppEntity.ID` requires `Hashable & Sendable` — `UInt64` already satisfies both, and per-type `ID` aliases cannot collide at the Swift level. Named per-kind Spotlight indexes prevent cross-kind collisions there. The remaining decision is whether to adopt typed wrapper structs (`PlaycutID`, `ShowID`, …) anyway for refactor safety; cheap at F1 but a minor net-negative on ergonomics. Commit to one approach before F5 lands so all entities follow it.
6. **Are there `AppIntentsPackage`-discovery issues we need to plan around?** `de99e7f3` reverted a regression in this space; whoever picks up F4 should understand the root cause before re-attempting any package extraction.
7. **Spotlight index size budget.** With accretive donation over months, how large can `wxyc.playcuts` grow before it becomes a problem? Need a TTL / pruning policy.

## Glossary (Apple article → WXYC)

| Article term | WXYC equivalent |
|---|---|
| `LandmarkEntity` | `PlaycutEntity` (or `ShowEntity` / `ArtistEntity`) |
| Per-landmark `OpenIntent` | `OpenPlaycut` / `OpenShow` / `OpenArtist` |
| `attributeSet.latitude` / `.longitude` | Used for C9 (artist origin) |
| `donateLandmarks(modelData:)` | `SpotlightDonationService` donation pipeline (F2) |
| `PhotoQuery` reindex handler | `PlaycutEntityQuery` reindex handler (F3) |
| `ShowInAppSearchResultsIntent` | C7 |

## References

- Apple Developer doc: [Making app entities available in Spotlight](https://developer.apple.com/documentation/AppIntents/making-app-entities-available-in-spotlight)
- Sample referenced by the article: Adopting App Intents to support system experiences
- This repo: `Shared/Intents/`, `Shared/AppServices/NowPlayingWidgetIntent.swift`, `Shared/Playlist/Sources/Playlist/PlaylistEntry.swift`, `Shared/Metadata/`, `WXYC/iOS/AppLifecycleModifier.swift`
- Reverted regression to understand before F4: `de99e7f3` (Revert AppIntentsPackage additions that broke AppShortcuts discovery)
- Related stubs: `Shared/SemanticIndex/` (empty package shell, May 2026)
