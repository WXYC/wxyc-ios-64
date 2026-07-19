# Touring Soon tab: filters, genre, and For You (#474)

Status: APPROVED (review 2026-07-13) — ticket chain filed 2026-07-13, no implementation started.

Parent issue: [wxyc-ios-64#474](https://github.com/WXYC/wxyc-ios-64/issues/474) (Phase 3 iOS: Touring Soon tab). Backend epic: [BS#1588](https://github.com/WXYC/Backend-Service/issues/1588). This plan covers the navigation prerequisite (a real tab bar), #474's base tab, and three feature releases with the cross-repo data work that powers them.

## Design decisions (locked 2026-07-13, via prototypes)

Two UI studies were built and adjudicated; their verdicts are recorded in the file headers:

- `docs/ideas/touring-soon-filters.html` — **B · Filter Sheet** won: one Filter button with an active-count badge, a bottom sheet holding all facets, applied-filter pills beside the button. Filtering is instant and client-side over a once-fetched window (the triangle-shows recipe: fetch once, filter an in-memory cache, re-render).
- `docs/ideas/touring-soon-reco-highlights.html` — **H2 · Pinned shelf** won, with **no For You mode**: recommendations render as an always-on horizontal "For You" rail above the date-ordered list whenever matches exist. The filter sheet stays facets-only; recommendations are content, not configuration.

Standing constraints from those sessions: WXYC's internal library genre taxonomy (`genre_artist_crossreference`) is a record-retrieval filing system and must not be presented externally — the presentation taxonomy is Discogs genres via LML, the same vocabulary the app already shows as Playcut Detail capsules. Likes are on-device only; taste data never leaves the device (see Privacy invariant).

## Release runway

Each release is independently shippable and none requires rework of the previous one. The load-bearing decision is made at R1: fetch the whole curated window once and filter in memory — that is what makes R2 and R3 pure additions.

| Release | Feature | New data plumbing |
|---|---|---|
| R0 | Root tab bar (replaces the paged root view) | None — pure iOS navigation change |
| R1 | Tab + instant filter sheet | None — `GET /concerts` already carries every facet |
| R2 | Genre filter section | LML artist-genre aggregation → BS enrichment → `Concert.genres` |
| R3a | Likes (hearts on playcuts) | `artist_id` exposed on V2 flowsheet entries |
| R3b | For You shelf | semantic-index neighbors-by-library-id → BS nightly enrichment → `Concert.similar_artists` |

## R0 — Root tab bar migration (prerequisite; ships with or before R1)

The app root today is a paged `TabView` (`WXYC/iOS/Views/Root/RootTabView.swift`: `.tabViewStyle(.page(indexDisplayMode: .always))`) holding two pages, Playlist and Info Detail. A third destination makes swipe-paging with dot indicators the wrong shape; Touring Soon needs a proper tab bar.

**Change.** Replace the paged style in `RootTabView` with a standard tab bar using the modern `Tab` API (per `docs/swiftui.md`): `Tab("Now Playing", systemImage:…)` / `Tab("Touring", …)` (added in R1) / `Tab("Info", …)`, with explicit selection values retaining the existing `Page` enum. Tab title "Touring"; systemImage chosen at implementation from ticket/calendar-family SF Symbols (`ticket`, `calendar`) to match the Box Office ticket language (`docs/ideas/touring-shows-box-office.html`). Keep the `overlaySheet` playcut-detail presentation and `selectedPlaycut` plumbing exactly as-is. The wallpaper must stay visible: the iOS 26 floating glass tab bar is translucent by default, so no opaque-background fight is expected — but verify against the Metal wallpaper on device, since opaque UIKit backing layers are exactly what killed `NavigationSplitView` here previously (see `docs/ideas`/nav-redesign history). This migration is deliberately minimal and does not take on the larger navigation-redesign hierarchy (sidebar on regular width, Explorer destination); it only swaps the paging affordance for a tab bar so a third tab can exist.

**Tests.** UI smoke: three tabs reachable, playcut detail sheet still presents from Playlist, wallpaper visible behind tab bar. Existing UI-test entry point per `docs/build-test.md`.

## R1 — Tab + instant filters (iOS only)

No backend or contract changes. `GET /concerts` (merged, BS#1603 / PR #1606) already serves every facet: embedded `Venue` (name/city; ~21 rows total), `starts_on`, `price_min` (0 = free), `age_restriction`, `status`, `curated`. Anonymous-session auth is already wired in `ConcertsFetcher` (`Shared/Concerts`).

**Architecture.** Fetch the full curated window on tab appearance, hold rows in an `@Observable` model, apply every filter as an in-memory predicate. No refetch on filter change; refresh on foreground/pull-to-refresh per the app's normal caching conventions.

**Central data holder.** `TouringSoonModel` in `Shared/Concerts` (public, `@MainActor @Observable`):

```swift
@MainActor @Observable public final class TouringSoonModel {
    public private(set) var phase: Phase          // .loading, .loaded, .failed(Error)
    public private(set) var allConcerts: [Concert] // full fetched window, starts_on ascending
    public var filter: ConcertFilterState          // facet state; mutations recompute `filtered`
    public var filtered: [Concert] { get }         // allConcerts.filter(filter.matches)
    public init(fetcher: ConcertsFetching)         // protocol seam; ConcertsFetcher conforms
    public func load() async                       // pagination exhaust, see below
}
```

Pagination exhaust in `load()`: request `curated=true`, `from=today` (station-local), `limit=100`, `page=1`, then keep requesting `page+1` while `pagination` indicates more results, appending each page; cap at a safety ceiling (10 pages) with a logged warning. Today this is one request (~9 events); the loop is wired now so the tab needs no rework as recall climbs (BS#1604). `ConcertFilterState` is a value type holding the facet selections with a pure `matches(_ concert: Concert) -> Bool`, unit-tested facet by facet and in combination.

Concurrency boundary (deliberate, documented for maintainers): unlike `PlaylistService` (an actor, because the flowsheet feed is shared across app/widget/CarPlay targets through `CacheCoordinator`), `TouringSoonModel` is `@MainActor`-bound UI state for one screen. Its `allConcerts` cache is UI-thread-only and is not shared with extensions or widgets; nothing outside the tab reads it. If a widget or watch surface ever wants concerts, the fetch layer (`ConcertsFetcher`) is the sharing seam — not this model — and that change would be a new design decision, not a refactor of this one. Filter mutations and pagination appends both happen on the main actor, so there is no cross-actor mutation to defend against.

**Filter model** (all client-side predicates):

- Date window: All / Tonight / This weekend / Next 7 days — cumulative windows computed on venue-local (`America/New_York`) calendar dates against `starts_on`. These predicates live in `Shared/Concerts` inside `ConcertFilterState`, reusing the package's existing `TimeZone+Station.swift`; the app target contains no date math.
- Venues: multi-select checklist grouped by city (CH–Carrboro / Durham / Raleigh / Saxapahaw), built from the distinct venues present in the fetched window. Unchecking every venue restores all (never a self-inflicted empty state).
- Free shows: `price_min == 0`.
- All ages: `age_restriction` is scraper free-text; normalize with `AgeRestrictionCategory` — a standalone exported `enum AgeRestrictionCategory: Sendable, Equatable { case unknown, allAges, restricted(minAge: Int) }` in `Shared/Concerts` with an `init(rawText: String?)` parser, applied per-concert; `ConcertFilterState` consumes the category, it does not own the parsing. Mapping (case-insensitive, whitespace-collapsed): `nil`/empty → `.unknown`; contains "all ages"/"AA" → `.allAges`; a leading integer N with "+"/"plus"/"and up"/"and over" → `.restricted(minAge: N)` (covers "18+", "21 PLUS", "18 and up"); anything else → `.unknown` with the raw string preserved for display and a debug log so new scraper phrasings surface in development. Toggle semantics: All-ages ON hides only `.restricted`; `.unknown` and `.allAges` remain visible (we never hide a show we can't prove is restricted).
- `status` renders as state, not a filter: `sold_out` badge, `cancelled` strikethrough + dim, `rescheduled` badge.

**UI.** New tab surface consistent with the existing tab structure. Header: title, "N of M shows" count line, Filter button with active-count badge, applied pills (tap a pill to clear that facet). Sheet: When segmented control, Venues checklist grouped by city, Free/All-ages toggles, Reset, live "Show N shows" CTA. Rows reuse `BoxOfficeTicketPresenter` so copy/styling match the playcut CTA and detail surfaces. Deliberate sparse state per #474 ("few shows matched", not "broken") plus a distinct filtered-to-zero state with a Clear-filters action. Loading and error states.

**Code placement** (mirrors the Box Office pattern: logic public in the package, views in the app target):

- `Shared/Concerts`: `ConcertFilterState` (facet state + predicates), `TouringSoonModel` (fetch/cache/filtered projection), age-restriction normalizer, venue grouping. All TDD-tested with `ConcertStubs`.
- App target (`WXYC/iOS/Views/...`): tab view, sheet view, pills, row layout.

**Acceptance** (from #474 plus the sheet): curated upcoming shows listed date-ordered; `curated`/`from`/`to`/pagination exercised; rows via `BoxOfficeTicketPresenter`, tap-through to detail/`ctaURL`; every filter applies instantly with visible count feedback; graceful sparse/empty/loading/error states.

## R2 — Genre filters

**Taxonomy decision.** Discogs *genres* (~15 coarse values — Rock, Electronic, Jazz, Folk World & Country, …) are the chip vocabulary; Discogs *styles* are too fine-grained for filtering and stay a detail-view treatment. Do not backfill from triangle-shows `raw_data.genre` (Ticketmaster taxonomy; mixing vocabularies) and do not use the internal library filing taxonomy (retrieval codes, not presentation). Curated shows all have resolved headliners, so LML-path coverage is structurally complete; unresolved (non-curated) shows simply carry no genre.

**Derivation.** Artist-level genre = frequency aggregation of `release_genre` rows across the artist's releases in the discogs-cache (LML already stores per-release genres/styles keyed by `release_id`; see `discogs/cache_service.py`). Majority-take, top 1–2 genres per artist.

**Pipe** (mirrors the proven `album_metadata.genres` pattern end-to-end):

1. **LML**: new API-key-gated endpoint (shape modeled on `POST /api/v1/streaming-check` / `identity/bulk`): bulk artist-genres — input a batch of `{artist_name, discogs_artist_id?}`, output per-artist `{genres: [string], styles: [string]}` aggregated from the cache, falling back to the Discogs API on cache miss. LML ticket; coordinate with the post-launch-hardening project (project 32) since LML lookup paths are an active epic (LML#338) — this is a new read surface, not a change to `lookup/orchestrator.py`, but file it into the project for visibility.
2. **Backend-Service**: nightly enrichment step chained after the concerts artist resolver (05:15 UTC): for resolved headliners lacking genre metadata, call the LML endpoint and persist artist-level `genres text[]` (new columns on the existing artist-level metadata table that already feeds `artist_bio`/`artist_wikipedia_url` into V2 — same persistence philosophy as BS#1336 for albums). `GET /concerts` projects `genres` via a LEFT JOIN. Backfill once at deploy.
3. **wxyc-shared**: `Concert.genres` in `api.yaml` — additive, non-breaking; `npm run generate`; `npm run check:breaking`. Proposed schema patch (on the `Concert` object; NOT added to `required`):

```yaml
genres:
  type: array
  nullable: true
  items: { type: string }
  description: >-
    Discogs genre tags for the resolved headlining artist, aggregated
    across their releases (LML discogs-cache, majority-take). Null when
    the headliner is unresolved or enrichment has not run. Same taxonomy
    as FlowsheetV2TrackEntry.genres.
```
4. **iOS**: `Concert` decodes `genres` (forward-compatible optional, same discipline as the flowsheet fields — can land before the backend emits it). Sheet gains a Genre section whose chips are the distinct genres present in the fetched window (never hardcoded; empty categories never render). Multi-select union semantics.

## R3a — Likes

**Superseded (2026-07-18) — see [`docs/plans/492-liked-songs.md`](492-liked-songs.md).** The likes model pivoted from artist likes to **song likes**: listeners like songs (playcut rows and the detail card are the gesture sites; a fourth root tab, "Liked", browses them), and the For You shelf (R3b, #493) derives its artist set as `distinct artistId across liked songs` — the same `likedArtistIds` shape R3b consumed under the artist-likes model, so R3b is unchanged in shape. The full decision record, architecture (PRs A/B/C), and acceptance criteria live in the 492 plan; the interaction design verdicts are recorded in the prototype study `docs/ideas/artist-likes-interactions.html`.

**Persistence reversal.** The SwiftData choice recorded here previously was reversed in the pivot: likes persist in a minimal Codable JSON file store (`Shared/LikedSongs`, `FileStorage` seam) — a first-in-repo `ModelContainer` wasn't worth it at this scale, `DefaultsStorage` would load unbounded snapshots into a launch-loaded plist, and the `Caching` package evicts by contract, which is wrong for user-curated never-evict data. See the 492 plan's decision #6.

**Governance — resolved.** The project-32 pre-clearance gate for exposing `artist_id` (additive, nullable) on the V2 flowsheet wire was filed as [BS#1625](https://github.com/WXYC/Backend-Service/issues/1625) and **approved 2026-07-18**; the field is live (BS PR #1698, deployed) and the wxyc-shared SSOT patch is wxyc-shared#239. R3a therefore proceeds with hearts on playcut rows — the approved path, not the Box Office fallback contemplated below the gate.

## R3b — For You shelf

**Recommendation derivation** (two tiers, both resolved on-device by set intersection over the cached window):

- **Loved**: `concert.headlining_artist_id ∈ likedIds`.
- **Similar**: `concert.similar_artists` (shipped with the feed) intersected with `likedIds`. Reason line names the intersecting liked artist ("Because you like Stereolab") — chosen by highest affinity weight when several intersect; the name comes from the local likes store, so the server never learns the listener's taste.

**Pipe**:

1. **semantic-index**: new endpoint — batch neighbors by library id: input catalog artist ids, output per-input neighbor list as `[{library_artist_id, weight}]` from the precomputed affinity blend (DJ-transition PMI, shared personnel/styles, label family, Wikidata influence, acoustic similarity). The entity table already maps graph artists to Backend library ids; this endpoint just speaks that key. semantic-index ticket.
2. **Backend-Service**: nightly step after the artist resolver: for each upcoming curated headliner, fetch top-K neighbors (K≈20), persist per concert (`concert_similar_artists` rows or a JSONB column), project on `GET /concerts` as `similar_artists: [{artist_id, weight}]`. Payload cost ~20 ids × ~50 concerts. semantic-index stays out of the listener hot path; its single-box SQLite API is only ever called nightly, server-to-server.
3. **wxyc-shared**: `Concert.similar_artists` in `api.yaml` — additive, non-breaking; regenerate; check-breaking. Proposed schema patch (on the `Concert` object; NOT added to `required`):

```yaml
similar_artists:
  type: array
  nullable: true
  items:
    type: object
    required: [artist_id, weight]
    properties:
      artist_id:
        type: integer
        description: WXYC catalog artist id (same keyspace as headlining_artist_id).
      weight:
        type: number
        description: semantic-index affinity score, descending order; used for client-side ranking and the similar-tier noise cap.
  description: >-
    Top-K affinity neighbors of the resolved headliner, computed nightly
    from the semantic-index graph. Null when the headliner is unresolved
    or enrichment has not run. Powers on-device For You matching.
```
4. **iOS**: For You shelf (H2): horizontal rail pinned above the list, rendered only when matches exist; loved cards first, then similar ranked by weight; noise cap on the similar tier — **top 3 by weight, remotely tunable via a PostHog feature flag** read through the existing `FeatureFlagProvider` protocol (local default 3 when the flag is absent/offline); reason lines per tier; card tap = same detail route as rows. Matching/ranking logic in `Shared/Concerts` (TDD; cap injected as a parameter), shelf view in the app target.

**Cold start**: no likes → empty intersection → no shelf → the tab is exactly R1's list. No onboarding needed.

## Cross-cutting

**Privacy invariant.** Likes and the derived taste profile never leave the device. No server-side likes (anonymous users/sessions are ephemeral and subject to pruning — attaching likes would create per-install state that evaporates on reinstall). If cross-device sync is wanted later, use iCloud (ubiquitous KV store or CloudKit private DB), which stays inside the listener's Apple ID. This invariant also constrains analytics: see below.

**Anonymous sessions.** No changes required in any release. All server reads remain the existing anonymously-authed surfaces (`GET /concerts`, V2 flowsheet).

**Analytics** (PostHog, per app conventions): filter-sheet opens, per-facet apply counts, filtered-to-zero occurrences, shelf impressions and card taps, like/unlike counts. Events are declarative `@AnalyticsEvent` structs in the established idiom (e.g. `TouringFilterApplied`, `TouringFilteredToZero`, `ForYouShelfImpression`, `ForYouCardTapped`, `ArtistLikeToggled`), injected via the settable-`AnalyticsService` pattern; exact names finalized at implementation. Events carry no artist identity for likes/shelf events (counts and tiers only) — decided 2026-07-13; loosening to artist-level product analytics would be a deliberate future opt-in.

**Contract discipline.** Every wire change lands in `wxyc-shared/api.yaml` first, regenerates all consumers, and passes `check:breaking`. iOS decodes are forward-compatible optionals that can land ahead of backend emission (established pattern: flowsheet `genres`/`styles`).

**Testing.** TDD throughout per repo standards. iOS logic (filter predicates, date windows, age normalizer, match/rank/cap) in package tests using `ConcertStubs` and WXYC-canonical fixtures; BS enrichment steps and read projections get integration specs alongside the existing concerts ETL tests; LML endpoint gets cache-hit/miss and aggregation tests; semantic-index endpoint gets identity-mapping tests.

## Ticket chain and sequencing

All tickets filed 2026-07-13, cross-referenced per org conventions (sub-issues + blocked-by; iOS tickets are sub-issues of #474, BS enrichment tickets of BS#1588; LML#781 and BS#1625 are on project 32). iOS work never waits on cross-repo tickets being *implemented* to start: R0/R1 have no dependencies at all, and the iOS decode changes (5, 11) use forward-compatible optionals that land ahead of backend emission — only the user-visible feature enablement gates on the backend being live in production.

0. **iOS — R0 root tab bar migration** — [wxyc-ios-64#489](https://github.com/WXYC/wxyc-ios-64/issues/489) (no dependencies). Small, can ship in the same release as R1 or earlier.
1. **iOS #474 sub-ticket — R1 tab + filter sheet** — [wxyc-ios-64#490](https://github.com/WXYC/wxyc-ios-64/issues/490) (blocked by 0). Ship first with R0.
2. **LML — bulk artist-genres endpoint** — [library-metadata-lookup#781](https://github.com/WXYC/library-metadata-lookup/issues/781) (independent; on project 32 for visibility).
3. **wxyc-shared — `Concert.genres`** — [wxyc-shared#221](https://github.com/WXYC/wxyc-shared/issues/221) (independent, additive; schema patch above).
4. **BS — artist-genre enrichment + `GET /concerts` projection** — [Backend-Service#1624](https://github.com/WXYC/Backend-Service/issues/1624) (blocked by 2, 3).
5. **iOS — R2 genre section** — [wxyc-ios-64#491](https://github.com/WXYC/wxyc-ios-64/issues/491) (decode lands any time; feature gated on 4 in prod).
6. **Project-32 exception request — `artist_id` on V2 flowsheet** — [Backend-Service#1625](https://github.com/WXYC/Backend-Service/issues/1625) (pre-clearance gate; see R3a Governance). Outcome recorded in this doc.
7. **iOS — R3a likes feature** — [wxyc-ios-64#492](https://github.com/WXYC/wxyc-ios-64/issues/492) (blocked by 6's resolution — either surface). Includes the Liked Artists list.
8. **semantic-index — neighbors-by-library-id endpoint** — [semantic-index#354](https://github.com/WXYC/semantic-index/issues/354) (independent).
9. **wxyc-shared — `Concert.similar_artists`** — [wxyc-shared#222](https://github.com/WXYC/wxyc-shared/issues/222) (independent, additive; schema patch above).
10. **BS — similar-artists nightly enrichment + projection** — [Backend-Service#1626](https://github.com/WXYC/Backend-Service/issues/1626) (blocked by 8, 9).
11. **iOS — R3b For You shelf** — [wxyc-ios-64#493](https://github.com/WXYC/wxyc-ios-64/issues/493) (blocked by 7, 10).

Every PR stays under the 1000-line guidance; the contract PRs are tiny and land early.

## Resolved decisions (2026-07-13)

- **Likes v1 scope**: hearts **plus a browsable Liked Artists list**, persisted via SwiftData. (Overrides the hearts-only default.)
- **Similar-tier noise cap**: top 3 similar matches shelved per window, by weight — **controlled by a PostHog feature flag** via `FeatureFlagProvider`, local default 3.
- **Analytics identity**: like/shelf events carry no artist ids (strictest reading of the privacy invariant). Loosening to artist-level product analytics is a deliberate future opt-in.

## References

- Issue #474; BS#1588 (epic), BS#1603/#1606 (read API), BS#1604 / triangle-shows#18 (recall limiter)
- Prototypes + verdicts: `docs/ideas/touring-soon-filters.html`, `docs/ideas/touring-soon-reco-highlights.html`
- Genre-capsule precedent: `docs/ideas/genre-capsules-v2-inline-payload.md`, BS#1336
- Fetch layer: `Shared/Concerts` (ConcertsFetcher, Concert, BoxOfficeTicketPresenter, ConcertStubs)
- Contract: `wxyc-shared/api.yaml` (`Concert`, `ConcertsResponse`, `GET /concerts`, `FlowsheetV2TrackEntry`)
