---
status: converted-to-tickets
source: extends `docs/ideas/spotlight-app-entities.md` to cover the On Tour feature
captured: 2026-07-23
converted: 2026-07-24
epic: https://github.com/WXYC/wxyc-ios-64/issues/423
subepic: https://github.com/WXYC/wxyc-ios-64/issues/619
related:
  - docs/ideas/spotlight-app-entities.md
  - docs/ideas/contextual-cues.md
  - docs/plans/474-touring-soon-tab.md
  - docs/ideas/on-tour-sharing.md
---

# Spotlight + App Entities — On Tour extension

> **Converted to tickets 2026-07-24** as sub-epic [#619](https://github.com/WXYC/wxyc-ios-64/issues/619) (children #620–#632). This is the On Tour half of the [Spotlight app entities epic (#423)](https://github.com/WXYC/wxyc-ios-64/issues/423). The parent epic was scoped 2026-07-08 around the *playlist graph* (playcuts, shows, artists, releases, labels, DJs); the **On Tour** feature — a browsable feed of Triangle-area concerts by WXYC-played artists — shipped and matured afterward and is entirely absent from the entity inventory. This doc proposes the concert/venue entities, the donation lifecycle, and the Siri/Spotlight capabilities that bring On Tour into the same retrieval story, in the same F/C/Q shape the parent doc uses. Ticket ids here are prefixed **`OT-`** so they don't collide with the parent epic's `F1…F5` / `C1…C10` / `Q1…Q2`.

## TL;DR

On Tour is arguably the **highest-value Spotlight/Siri surface in the whole app**, because a concert query is time-bounded, place-bounded, and high-intent: "Is Jessica Pratt playing near me?" / "What WXYC artists are touring this weekend?" The answer already lives in the fetched curated window, and — unusually — most of the *retrieval plumbing already exists*: On Tour sharing (#536/#537) shipped `WXYCDeepLink.concert`, `ConcertOpenMessage`, `Concert.shareURL`, and the `OnTourModel.resolveConcert(id:)` resolution ladder. What's missing is the App Intents layer on top: no `ConcertEntity`, no `wxyc.concerts` Spotlight index, no `OpenConcert: OpenIntent`, no Siri query.

The one genuinely new design problem — the thing that keeps this from being a copy-paste of the playcut work — is a **lifecycle inversion**. Playcuts are historical facts: a play that aired is permanently true, so `wxyc.playcuts` grows accretively and old rows never lie. Concerts are *ephemeral future events*: a Spotlight hit for a show that already happened is worse than useless. So the concert index needs the opposite discipline — **active expiry and reconcile-don't-append donation** — and that is the load-bearing foundation ticket (OT-F2), not the entity declaration.

## Why On Tour belongs in the Spotlight epic

1. **The marquee Siri query for the app is an On Tour query.** "What WXYC artists are touring near me / this weekend?" is higher-intent and more naturally conversational than anything in the playlist graph, and the destination view (On Tour tab + poster detail) already exists — so it ships with **no new in-app views**, unlike the parent epic's C5/C7.
2. **Concerts are the app's only genuinely geographic content.** Venues carry `city`/`state`/`address`; `CSSearchableItemAttributeSet` carries `latitude`/`longitude`/`supportsNavigation`/`namedLocation`. This is the concrete, data-backed realization of the parent epic's **C9 (#442, "geographic affordances for local NC artists")**, which is currently vague and blocked on a nonexistent artist-origin data source. Venues supersede artist-origins as the geographic axis — see OT-C4.
3. **The relevance signal is already computed.** `ForYouShelf` (`Shared/Concerts/Sources/Concerts/ForYouShelf.swift`) already ranks the window into `loved` (headliner is a liked artist) and `stationRecommended` tiers. Those are exactly the concerts worth donating at elevated priority; donating the whole Triangle calendar would be noise.
4. **`OpenConcert` is nearly free.** The scheme handler in `AppLifecycleModifier` already posts `ConcertOpenMessage(.scheme)`, `Singletonia.startObservingConcertOpen()` stashes it as a `PendingConcertLink`, and `OnTourTabView` consumes it via `model.resolveConcert(id:)`. An `OpenConcert: OpenIntent` posts the same message — the entire downstream ladder is reused verbatim, exactly as `OpenPlaycut` posts `PlaycutOpenMessage`.
5. **Rich display representation out of the box.** A concert already carries a poster (`imageURL`), a headliner, a venue, a date, a price range, and a status pill — a Spotlight result row that's immediately useful, no synthesis required.

## Current state (snapshot 2026-07-23)

### What already ships for On Tour retrieval

| Surface | Type | Location |
|---|---|---|
| `WXYCDeepLink.concert(Int)` | Parses `wxyc://concert/<id>` **and** `https://wxyc.org/shows/<id>` | `Shared/Intents/Sources/Intents/WXYCDeepLink.swift` |
| `ConcertOpenMessage` | Typed `MainActorNotificationMessage`, `.universalLink` / `.scheme` source | `Shared/Intents/Sources/Intents/ConcertOpenMessage.swift` |
| `Concert.shareURL` | `https://wxyc.org/shows/<id>` (AASA-registered `/shows/*`) | `Shared/Concerts/Sources/Concerts/Concert.swift:342` |
| `OnTourModel.resolveConcert(id:)` | Three-rung ladder: window → by-id fetch → missed | `Shared/Concerts/Sources/Concerts/OnTourModel.swift:153` |
| `ConcertsFetching.fetchConcert(id:)` | Single-concert fetch (the by-id rung) | `Shared/Concerts/Sources/Concerts/ConcertsFetching.swift` |
| Concert-open observer | `Singletonia.startObservingConcertOpen()` → `PendingConcertLink` → `OnTourTabView` | `WXYC/iOS/Singletonia.swift:446`, `WXYC/iOS/Views/OnTour/OnTourTabView.swift:300` |

The through-line: **a concert id already routes to the On Tour poster detail from a universal link or the `wxyc://` scheme.** Every retrieval capability below is "make Spotlight/Siri able to *produce* that id," and the id→view half is done.

### What does *not* exist yet

- No `ConcertEntity` / `VenueEntity` (no `AppEntity` for On Tour content).
- No `wxyc.concerts` / `wxyc.venues` `CSSearchableIndex`. The playcut index (`CoreSpotlightIndexer.indexName = "wxyc.playcuts"`, `Shared/AppServices/Sources/AppServices/SpotlightIndexer.swift`) is playcut-only: its one method is `indexPlaycuts(_:priority:)`.
- No `OpenConcert` / `OpenVenue` `OpenIntent`.
- No concert Siri intent. `WXYCAppShortcuts` (`WXYC/iOS/Intents.swift:181`) registers `WhatsPlayingOnWXYC`, `PlayWXYC`, `MakeARequest` — nothing touches concerts.
- No concert donation. `SpotlightDonationService` (`Shared/AppServices/…/SpotlightDonationService.swift`) is watermark-based (`donateRecentPlaycuts` advances a monotonic `chronOrderID` high-water mark) — the wrong model for a churning, expiring concert window (see the crux below).

### On Tour data already shaped like entities

- **`Concert`** (`Shared/Concerts/…/Concert.swift`) — the obvious primary entity. Carries `id: Int`, embedded `venue: Venue`, `startsOn`/`startsAt`/`doorsAt`, `headlineName`, `headliningArtistId: Int?` (the join key to likes), `supportingArtistsRaw`, `imageURL` (poster), `ctaURL`, `priceMin`/`priceMax`, `ageRestriction`, `status: ShowStatus`, `genres: [String]?`, `similarArtists`, `stationRecommended`/`stationRecommendedRank`, `artistBio`, and `shareURL`.
- **`Venue`** (embedded) — `id: Int`, `slug` (stable, tint/geo seed), `name`, `city`, `state`, `address: String?`. **No coordinates on the wire** (documented in `Concert.swift`) — the geo story needs a source (OT-C4).
- **`ForYouRecommendation` / `ForYouShelf.recommendations(…)`** — the pre-computed `loved` / `stationRecommended` relevance signal, the natural priority input for donation.
- **`VenueRegionGroup` / `VenueGrouping`** — the Triangle venue set grouped into four stable regions (Chapel Hill–Carrboro / Durham / Raleigh / Saxapahaw). A small, slow-changing set — which is what makes a bundled venue→coordinate table viable.

## The crux: concert lifecycle vs. accretive index

This is the single design decision everything else hangs off, and it's why On Tour can't reuse the F2/F3 playcut machinery verbatim.

| | Playcut index (`wxyc.playcuts`) | Concert index (`wxyc.concerts`) |
|---|---|---|
| Truth model | Historical fact — permanently true | Future event — true only until it happens |
| Growth | Accretive; old rows kept | **Windowed**; past rows must be evicted |
| Donation | Append newer-than-watermark | **Reconcile** current window vs. indexed set |
| Volatility | Metadata enriches, id stable | Status churns (`on_sale`→`sold_out`→`cancelled`), shows drop out |
| Stale row | Harmless ("we played this") | **Harmful** (sends a listener to a show that's over) |

Two mechanisms, used together:

1. **Expiry via `attributeSet.expirationDate`.** Set each donated concert's expiration to the end of its show day (`startsOn` + a small margin, station zone). Spotlight auto-evicts the item once it passes — no polling, no cleanup pass. This is the primary, cheap defense against elapsed shows and the main reason concerts fit CoreSpotlight cleanly.
2. **Reconcile-and-evict on refresh.** On each On Tour window load, diff the fetched window against the last-donated id set: `indexAppEntities` upserts the present, and `CSSearchableIndex.deleteSearchableItems(withIdentifiers:)` removes concerts that left the window early — a **cancellation before the show date**, which expiration alone wouldn't catch. The last-donated id set lives in `DefaultsStorage` (a set of ids, not a monotonic watermark — the watermark idiom is specifically what does *not* transfer from the playcut service).

Everything downstream (priority weighting, geo, Siri) is comparatively conventional; this lifecycle discipline is the ticket that earns the "L" and deserves the most test coverage.

## Privacy — donation stays on-device, likes never leave

On Tour's hard invariant (repeated across `ForYouShelf`, the DTO doc comments, and the analytics): **no taste signal ever reaches the server.** The Spotlight work must preserve it, and it does so naturally:

- The `CSSearchableIndex` is **local to the device.** Donating the listener's `loved` concerts (matched against on-device likes) to the *local* index does **not** leak taste — nothing crosses the network. State this explicitly in OT-F2 so a future reviewer doesn't "fix" a non-problem.
- A likes-aware Siri intent (OT-C2's "artists you've heard") must do the intersection **on-device**, over the already-fetched public curated window — exactly as `ForYouShelf` does. It must never POST liked-artist ids to `/concerts`. The window fetch is `curated=true` (public, identical for every listener); the personal filter is a local set-intersection.
- Donation analytics (OT-Q1) count volume only — `concerts_donated`, `concerts_evicted`, `concert_reindex_requested` — **never** which concert or artist, matching the identity-free On Tour event taxonomy.

## Proposed entity inventory

| Entity | Source | Index name | Notes |
|---|---|---|---|
| `ConcertEntity` | `Concert` | `wxyc.concerts` | Primary. Windowed + expiring. Poster thumbnail, geo via embedded venue, keywords from genres + supporting acts + venue. |
| `VenueEntity` | `Venue` | `wxyc.venues` | Tiny, slow-changing set (~Triangle venues). The geographic anchor; `supportsNavigation`. |
| `ArtistEntity` *(not new)* | `#430` (parent epic F5b) | `wxyc.artists` | **Cross-link, not a new type.** A resolved headliner (`headliningArtistId`) *is* an `ArtistEntity`; OT-C6 gives it an "upcoming concert" relationship — the seam where On Tour meets the playlist graph. |

Out of scope: a `GenreEntity` (genres stay `keywords`), per-supporting-act entities (supporting artists are `keywords`, not entities), a `ShowStatus`/`TicketEntity` (status is an attribute, not a searchable thing).

## Identifier strategy

The parent epic settled on `EntityID<Owner>` — a phantom-typed `UInt64` wrapper (`Shared/Intents/…/EntityID.swift`) — so `PlaycutID` and `ShowID` can't cross-assign. Concerts introduce a mismatch to resolve up front:

- `EntityID<Owner>.value` is `UInt64`; `Concert.id` is `Int`; `WXYCDeepLink.concert` carries a raw `Int`.

**Recommendation:** `typealias ConcertID = EntityID<ConcertEntity>`, constructed as `EntityID(UInt64(concert.id))` (backend ids are positive serials; guard the negative case defensively → treat as unresolvable). **Keep `WXYCDeepLink.concert(Int)` and the `/shows/<id>` share URL exactly as shipped** — the `Int` is what the backend and the public link speak, and the sharing code (#536/#537) is live. The two representations coexist: `ConcertID` for the AppEntity/Spotlight identity, `Int` for the URL surfaces, with a one-line bridge each way. This is lower blast-radius than either generalizing `EntityID` over its raw type (churns `PlaycutID` ergonomics) or retyping the shipped deep link. Decide this in OT-F1 so OT-F4's `VenueID` follows suit.

## Indexing & expiry strategy

- **Named indexes** `wxyc.concerts` and `wxyc.venues` — scoped deletes/reindex, never `.default()`, matching `CoreSpotlightIndexer`'s rationale.
- **Donation triggers**:
  - On On Tour window load / refresh (`OnTourModel` already fetches the whole curated window once) — reconcile the full window.
  - On concert `status` transition observed in a refresh (sold out / cancelled) — re-donate that row (upsert) or evict it (cancelled).
  - Optionally from `BackgroundRefreshController` as the belt-and-suspenders batch site, mirroring how the playcut batch already rides background refresh — but bounded to the curated window (≤100 rows), and only if we want Spotlight warm without opening the tab.
- **Priority knobs**, sourced from `ForYouShelf`'s tiering (no behavior data needed):
  - `loved` (headliner is a liked artist) → elevated (mirror `currentPlaycutPriority = 500`).
  - `stationRecommended` → normal (`batchPriority = 100`).
  - everything else in the window → low.
  - Sooner shows (`startsOn` within 7 days) → a recency bump on top.
- **Expiry**: `attributeSet.expirationDate = endOfDay(startsOn, station zone)`.
- **Reindex policy** (OT-F3): `reindexAllEntities` re-donates the current curated window; `reindexEntities(for:)` resolves single ids via `fetchConcert(id:)` — the same by-id rung `resolveConcert` already uses.

## Geographic strategy for `VenueEntity`

`Venue` has no coordinates on the wire, so OT-C4 needs a source. Three options, cheapest first:

1. **Bundled `slug → (lat, lon)` table (recommended for v1).** The Triangle venue set is small and stable (`VenueGrouping` enumerates four regions; the real venue list is on the order of a couple dozen). A checked-in plist keyed by the stable `Venue.slug` gives coordinates with **zero backend dependency and zero runtime cost**. Unknown slug → no geo (graceful; the entity still indexes as a searchable name).
2. **On-device `CLGeocoder` over `Venue.address`, cached.** Works for any venue, but adds an async geocode + a permission-free-but-rate-limited network path and a cache to manage. Reasonable fallback for venues absent from the bundled table.
3. **Backend `latitude`/`longitude` on the `Venue` schema (clean long-term).** Cross-repo (`wxyc-shared/api.yaml` → Backend-Service → the iOS `Venue`). The right eventual home, but gated on the On Tour project's backend cadence — defer, and let the bundled table carry v1.

With coordinates set (`attributeSet.latitude/longitude`, `supportsNavigation = true`, `namedLocation = venue.name`), Maps and Spotlight can offer directions to "Cat's Cradle," and OT-C2's "near me" variant gets a real distance to sort by. **This is the ticket that fulfills the parent epic's C9 (#442)** — recommend re-scoping or closing #442 as superseded by OT-C4.

## iOS 26 / 27 API posture

The app's deployment floor is **iOS 18.6** (target 26, backporting per `CLAUDE.md`), so every entity here is built on the **universal iOS 18 `IndexedEntity` / CoreSpotlight baseline** — the same floor the parent epic's `PlaycutEntity` uses. Newer App Intents APIs are adopted only as **runtime-gated enhancements**, never as the baseline. Three tiers:

| API | SDK floor | Adopted by | Gating |
|---|---|---|---|
| `IndexedEntity`, `CSSearchableIndex`, `OpenIntent`, `EntityQuery` | iOS 18 | OT-F1–F4, OT-C1/C3/C4, donation | **None** — universal; the whole On Tour entity core runs on the 18.6 floor as-is. |
| Interactive `SnippetIntent` (`reload()`, in-snippet buttons) | iOS **26** | OT-C2 | **Runtime `@available(iOS 26, *)` only** — the 26 SDK is what Xcode 26.6 builds against, so no compile-time fence is needed. |
| `@AppIntent(schema:)` / `@AppEntity(schema:)` assistant schemas | iOS 27 | — | **N/A**: the schema domains are audio (`.audio.song`/`.artist`/`.album`/`.liveRadioStation`/`.radioShow`) + mail/photos/messages/books/journal/etc. **No events/venues/places/calendar domain exists**, so a concert/venue stays a **custom `AppEntity`** — the same call `docs/ideas/contextual-cues.md` made for Label/DJ/Flowsheet. Nothing to adopt, nothing to gate. |

Two App-Intents-specific rules the shipped audio-schema work (#450/#494) already encodes, restated so the On Tour tickets don't relearn them:

1. **iOS-27-SDK-only symbols need a *compile-time* fence too.** `PlayWXYCAudio` / `LiveRadioStationEntity` carry **both** `#if compiler(>=6.4)` (the `.audio.*` schema symbols don't exist in the Xcode 26.6 toolchain CI uses, so a runtime `@available` alone won't compile) **and** `@available(iOS 27.0, *)`. On Tour dodges this entirely — its only newer API (interactive Snippets) is iOS **26**, already in the 26 SDK, so a lone `@available(iOS 26, *)` suffices. The double-fence gymnastics are a 27-schema problem, and On Tour adopts no schema.
2. **Gate the *type* + ship a universal sibling; never branch inline, never gate the provider.** App Intents discovery is build-time metadata extraction, so availability is expressed on the whole intent/entity type, with a parallel always-available fallback (`PlayWXYCAudio` sits beside the universal `PlayWXYC` — "pre-iOS-27 voice playback stays on the `PlayWXYC` path"). Critically, **`WXYCAppShortcuts` (the `AppShortcutsProvider`) is never gated** — gate the individual shortcuts inside it. Mis-scoping discovery is exactly what made the *entire app* vanish from Shortcuts/Spotlight in **#392**; that failure is silent and total, so any gated surface needs a discovery check on a real 18.6 device/sim, not just a green compile.

**Reach argument.** Because the app already targets iOS 26, the interactive-Snippet enhancement (OT-C2) reaches a real, growing slice of users today — unlike iOS 27 schema/annotation work, which the sister epic rates **P3 "v0-dormant"** (near-zero reach at the 18.6 floor). For On Tour, the iOS 26 Snippet is the better near-term modern-API bet on both fit and reach; anything iOS 27 stays out of scope until the floor lifts.

## Backlog

Each item is sized **S/M/L/XL** and tagged with prerequisites, matching the parent doc's convention.

> **Parent-epic status (updated 2026-07-24).** Most of the playcut patterns OT-F3/OT-C3/OT-C6 mirror have **landed on master**: #427 (F3 reindex → `PlaycutEntityQuery+IndexedEntityQuery.swift` + `PlaycutReindexer.swift`), #430 (all F5 entities, incl. `ShowEntity`/`ArtistEntity`), and #435 (C2 thumbnail). Only **#428 (F4 — register `OpenIntent` shortcuts)** remains open, so **OT-C1 (#624)** is the one child still gated on a parent ticket. OT-F1/OT-F2 establish new patterns and are startable on master today — coordinate the `Shared/Intents/Package.swift` edit to avoid a manifest merge collision with any in-flight parent branch.

### Foundation

#### OT-F1. `ConcertEntity` + query + `OpenConcert`
- **Scope**: M.
- **What**: `ConcertEntity: AppEntity, IndexedEntity` from `Concert`; `ConcertEntityQuery: EntityQuery, IndexedEntityQuery` with an injectable source (mirror `PlaycutEntityQuery`'s `@Sendable ([id]) async -> [Concert]` seam, safe empty default); `OpenConcert: AppIntent, OpenIntent` whose `perform()` posts `ConcertOpenMessage(concertID:source:.scheme)`. Adopt `ConcertID = EntityID<ConcertEntity>` per the identifier decision.
- **Why cheap**: the id→view half is already live — `OpenConcert` reuses the `ConcertOpenMessage` observer + `resolveConcert` ladder with no new routing.
- **Naming (a live trap)**: `ConcertEntity` / `wxyc.concerts`, **not** `Show*`. The parent epic's `ShowEntity` models a **radio DJ airing** (index `wxyc.shows`), but On Tour concerts speak "show" everywhere else — the share URL is `/shows/<id>` (`Concert.swift:342`), the status enum is `ShowStatus`, and `WXYCDeepLink.concert`'s own doc comment calls it "a shared On Tour show". Keep the concert entity distinct so it can't collide with `wxyc.shows`; the web `/shows/*` namespace now backs **two** entity kinds (a radio airing and a touring concert), and nobody should "align" the concert entity to the `Show*` naming.
- **Package placement**: put `ConcertEntity` in `Shared/Intents` alongside `PlaycutEntity` (the parent doc's F5 stance: entities live here so `WXYCAppShortcuts` can reach them without a separate package). This requires adding a **`Concerts` dependency to `Shared/Intents/Package.swift`** (today it depends on `Playlist`, not `Concerts`; the dependency is acyclic — `Concerts` is pure domain). ⚠️ Re-read the `de99e7f3` (#392) revert first: a separate `AppIntentsPackage` broke `AppShortcuts` discovery — do **not** introduce a new package for these declarations.
- **Tests (TDD)**: add the existing `ConcertsTesting` product to the `WXYCIntentsTests` target (mirroring how the playcut entity tests depend on `PlaylistTesting`), so `ConcertEntity`/`ConcertEntityQuery` tests start red against real `Concert.stub(…)` fixtures rather than hand-built literals.
- **Platform gating**: `#if !os(watchOS) && !os(tvOS)` on the `IndexedEntity`/`CSSearchableItemAttributeSet` conformance, exactly as `PlaycutEntity`. (On Tour is iOS-only anyway.)
- **Out of scope**: donation (OT-F2). This PR just makes a concert addressable as an entity.

#### OT-F2. Concert donation service with expiry + reconcile *(the crux)*
- **Scope**: L.
- **What**: A `ConcertSpotlightDonationService` (in `AppServices`) + a `ConcertSpotlightIndexer` seam targeting `wxyc.concerts`. **Reconcile semantics, not a watermark**: diff the fetched window against the persisted last-donated id set, `indexAppEntities` the present rows with `ForYouShelf`-derived priority, `deleteSearchableItems(withIdentifiers:)` the departed, and set `attributeSet.expirationDate` per row. Sourced from `OnTourModel`'s already-fetched window.
- **Package placement**: add a **`Concerts` dependency to the `AppServices` target** (`Shared/AppServices/Package.swift`). Today it depends on `Playlist` + a platform-conditioned `WXYCIntents` (`SpotlightDonationService.swift` imports both) but **not** `Concerts`, and this service references `ForYouShelf`/`Concert`/`OnTourModel`. Acyclic (`Concerts` depends only on `Core`/`Logger`); the CoreSpotlight-touching code stays under the same `#if !os(watchOS) && !os(tvOS)` gate as the playcut service.
- **Prereqs**: OT-F1.
- **Risks**: this is the ticket that's genuinely new relative to the playcut path — the watermark idiom does not transfer. Heaviest test coverage: expiry set correctly (station-zone end-of-day), cancelled-before-date eviction, dedup so a re-broadcast window doesn't burn XPC, background-refresh budget bound (≤ the ~100-row curated window).
- **Privacy**: donation is on-device; the local index never leaves the phone — state it in the doc comment.

#### OT-F3. `ConcertEntity` reindex handlers
- **Scope**: S.
- **What**: `reindexEntities(for:indexDescription:)` (resolve ids via `fetchConcert(id:)`) and `reindexAllEntities(indexDescription:)` (re-donate the curated window) on `ConcertEntityQuery`.
- **Prereqs**: OT-F1, OT-F2.

#### OT-F4. `VenueEntity` type + minimal query
- **Scope**: S–M.
- **What**: bare `VenueEntity: AppEntity` (+ `IndexedEntity`) and a minimal `EntityQuery` derived from the venues present in the concert window. No geo yet (OT-C4), no donation pipeline yet — the declaration only, so OT-C4 and any contextual-cue consumer can reference the type. Sibling to the parent epic's F5.
- **Prereqs**: OT-F1 (the `EntityID` decision).

### Capabilities

#### OT-C1. App Shortcuts phrases for `OpenConcert`
- **Scope**: S.
- **What**: add `AppShortcut` entries to `WXYCAppShortcuts` (`WXYC/iOS/Intents.swift:181`) for `OpenConcert` with example phrases. Additive, like the parent epic's F4.
- **Prereqs**: OT-F1.

#### OT-C2. "What WXYC artists are touring near me / this weekend?" *(marquee)*
- **Scope**: M.
- **What**: a discoverable `AppIntent` returning `[ConcertEntity]` with `ProvidesDialog`, filtering the fetched curated window by an optional **date window** (this weekend / next 7 days) and an optional **"artists you've heard"** intersection (local likes) and/or **proximity**. Register phrases in `WXYCAppShortcuts`.
- **Interactive snippet (iOS 26+)**: on iOS 26+, attach an interactive `SnippetIntent` so the answer is an actionable card in the Siri/Spotlight surface — poster + date + venue, with in-snippet **Get Tickets** (`Concert.ctaURL`) and **Add to Calendar** (reusing OT-C7's `ConcertCalendarEvent`) buttons, refreshable via `reload()` — without opening the app. Below iOS 26 the intent degrades to the universal static snippet / plain `ProvidesDialog`. Gate the `SnippetIntent` **type** with `@available(iOS 26, *)` only (no `#if compiler` fence — see *iOS 26 / 27 API posture*); the outer intent stays universal on the 18.6 floor.
- **Why**: the single highest-value item — high-intent, conversational, and the destination view already exists (no new UI), with the interactive snippet delivering the answer without a launch.
- **Prereqs**: OT-F1; the "near me" proximity sort also wants OT-C4's coordinates; the in-snippet "Add to Calendar" wants OT-C7.
- **Risks / staging**: proximity needs **CoreLocation when-in-use** — a new permission surface. Ship the **date-window variant first (no new permission)**; add proximity as a follow-on gated on location auth. The likes intersection stays on-device (privacy invariant).

#### OT-C3. Concert poster as Spotlight thumbnail
- **Scope**: S.
- **What**: surface `Concert.imageURL` as the result thumbnail. **Mirror `PlaycutEntity`'s approach** (`set.thumbnailURL = artworkURL`, a remote URL — `PlaycutEntity.swift:103`) so concerts follow the same established plumbing; verify the remote-vs-local `thumbnailURL` behavior once and reuse the verdict for both.
- **Prereqs**: OT-F1.

#### OT-C4. `VenueEntity` geographic affordances *(fulfills parent C9/#442)*
- **Scope**: M.
- **What**: bundled `slug → (lat, lon)` table (see geo strategy); set `latitude`/`longitude`/`supportsNavigation`/`namedLocation` on `VenueEntity.attributeSet`; `OpenVenue: OpenIntent`; a venue query that backs into the window ("what's on at Cat's Cradle?"). Cross-reference #442 for closure-as-superseded.
- **Prereqs**: OT-F4. Optionally the backend venue-coordinate field (deferred).

#### OT-C5. Re-donate / evict on status change
- **Scope**: S.
- **What**: when a refresh observes a concert's `status` transition (sold out / cancelled) or its departure from the window, re-donate (upsert) or evict that single row. Analog of the parent epic's C10, but load-bearing here because concert status is volatile. May fold into OT-F2's reconcile if that ticket already diffs on identity + status.
- **Prereqs**: OT-F2.

#### OT-C6. `ArtistEntity` ↔ touring cross-link
- **Scope**: M.
- **What**: give the parent epic's `ArtistEntity` (#430) an "upcoming Triangle concert" relationship, resolved by `Concert.headliningArtistId == artist.id`. The connective tissue between the playlist graph and On Tour — and the seam to the contextual-cues epic (#424): "the artist now playing on air is touring near you."
- **Prereqs**: OT-F1 **and** #430 (parent epic F5b) must have shipped `ArtistEntity`.

#### OT-C7. "Add this show to my calendar" from Siri/Spotlight *(optional)*
- **Scope**: S–M.
- **What**: reuse the shipped `ConcertCalendarEvent` (On Tour "Add to Calendar", #538) behind an intent so a concert entity can be added to Calendar conversationally.
- **Prereqs**: OT-F1.

### Internal / QA

#### OT-Q1. Identity-free donation analytics
- **Scope**: S.
- **What**: typed `AnalyticsService` events `concerts_donated`, `concerts_evicted`, `concert_reindex_requested` (volume only, **no artist/concert identity** — On Tour taxonomy). Mirrors the parent epic's Q2 and the post-#139 analytics pattern.
- **Prereqs**: OT-F2.

#### OT-Q2. Expiry / eviction verification
- **Scope**: S.
- **What**: tests asserting a past-dated concert is absent from the index after expiry, a cancelled concert is evicted on reconcile, and (DEBUG) a small inspector to dump the `wxyc.concerts` index for triage.
- **Prereqs**: OT-F2.

## Sequencing (recommended)

```
OT-F1 → OT-F2 → OT-F3
   ↘        ↘
    OT-C1    OT-C5           (status churn; may fold into OT-F2)
    OT-C2    OT-Q1 OT-Q2     (analytics/QA, any time after OT-F2)
    OT-C3
    OT-F4 → OT-C4            (venues + geo; fulfills #442)
    OT-C6                    (needs #430 ArtistEntity)
    OT-C7                    (calendar; optional)
```

**A shippable v1 is OT-F1 + OT-F2 + OT-F3 + OT-C1 + OT-C2 (date-window variant) + OT-C3** — "WXYC-artist concerts show up in Spotlight with posters, you can ask Siri what's touring this weekend, and a tap opens the On Tour poster detail; past shows auto-expire." It needs **no new in-app views** (the On Tour tab + poster detail already exist), which is what makes it a tighter v1 than the parent epic's own.

**v2**: OT-F4 + OT-C4 (venues + geo, closes #442) + OT-C5.
**v3 / conditional**: OT-C6 (needs #430), OT-C7, and the backend venue-coordinate field.

## Relationship to the contextual-cues epic (#424)

The retrieval framing (this doc) is "find a concert you're not looking at." The **real-time** framing — "the artist now playing on air is touring near you," surfaced while the Now Playing view is on screen — belongs to #424, and it *consumes* `ConcertEntity` + the `ArtistEntity`↔touring relationship declared here (OT-F1/OT-C6). Declare the types here; let #424 annotate the live surfaces. Note the seam in both epics so the dependency is explicit.

## Open questions for ticketing

1. **Sub-epic vs. flat sub-issues?** The OT-* cluster is ~11 tickets — recommend a **sub-epic under #423** ("On Tour app entities") parenting them, mirroring how #423 parents its own F/C/Q, rather than flattening them into #423's existing list.
2. **Background-refresh donation, or tab-open only?** Donating the curated window on background refresh keeps Spotlight warm without opening the tab, at a background-budget cost. Or donate lazily on first On Tour open — simpler, but Spotlight is cold until the user visits the tab once. Which matches the product intent?
3. **Proximity in OT-C2** — is a new CoreLocation permission worth the "near me" sort in v1, or is the date-window variant enough to ship first? (This doc assumes date-window-first.)
4. **Venue coordinate source** — bundled table now vs. wait for a backend `Venue.latitude/longitude`? (This doc recommends the bundled table for v1, backend field later.)
5. **#442 disposition** — re-scope to point at OT-C4, or close as superseded once OT-C4 is filed?
6. **`ConcertID` typing** — confirm the `EntityID<ConcertEntity>` (UInt64) + raw-`Int` deep-link coexistence over retyping the shipped deep link.

## Glossary (parent doc → On Tour)

| Parent-doc term | On Tour equivalent |
|---|---|
| `PlaycutEntity` / `wxyc.playcuts` | `ConcertEntity` / `wxyc.concerts` |
| `OpenPlaycut` / `PlaycutOpenMessage` | `OpenConcert` / `ConcertOpenMessage` *(already exists)* |
| `SpotlightDonationService` (watermark) | `ConcertSpotlightDonationService` (**reconcile + expiry**) |
| `ShowEntity` / `wxyc.shows` (radio DJ airing) | **distinct** — `ConcertEntity` / `wxyc.concerts` (touring show); don't merge the two |
| accretive index, keep old rows | **windowed** index, evict past rows via `expirationDate` |
| C9 artist-origin geo (blocked) | OT-C4 venue geo (bundled coordinates) |
| C2 album-art thumbnail | OT-C3 concert-poster thumbnail |

## References

- Parent epic: [#423](https://github.com/WXYC/wxyc-ios-64/issues/423); backlog doc `docs/ideas/spotlight-app-entities.md`
- Sister epic: [#424](https://github.com/WXYC/wxyc-ios-64/issues/424); doc `docs/ideas/contextual-cues.md`
- On Tour tab plan: `docs/plans/474-touring-soon-tab.md`; sharing: `docs/ideas/on-tour-sharing.md`; poster detail: `docs/plans/on-tour-poster-detail.md`
- Repo touchpoints: `Shared/Intents/` (`PlaycutEntity`, `EntityID`, `WXYCDeepLink`, `ConcertOpenMessage`), `Shared/AppServices/` (`SpotlightDonationService`, `SpotlightIndexer`), `Shared/Concerts/` (`Concert`, `Venue`, `OnTourModel`, `ForYouShelf`, `VenueGrouping`, `ConcertsFetching`), `WXYC/iOS/Intents.swift` (`WXYCAppShortcuts`), `WXYC/iOS/Singletonia.swift` (concert-open observer)
- Apple: [Making app entities available in Spotlight](https://developer.apple.com/documentation/AppIntents/making-app-entities-available-in-spotlight); `CSSearchableItemAttributeSet.expirationDate`; `CSSearchableIndex.deleteSearchableItems(withIdentifiers:)`
- Discovery-regression lesson before any package extraction: `de99e7f3` (#392)
