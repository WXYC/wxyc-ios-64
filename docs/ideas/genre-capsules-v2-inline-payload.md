# Restore genre capsules via the V2 flowsheet inline payload

## Problem

The Playcut Detail card stopped rendering genre/style capsules. Two independent regressions, both fallout from the post-launch cache-first hardening, combine so that genres reach the detail view in essentially no path:

1. **iOS — V2 inline short-circuit.** When a V2 flowsheet row carries at least one streaming URL inline (now the common case once enrichment lands), `PlaycutMetadataService.fetchMetadata(for:inline:)` returns the inline metadata directly and never calls `/proxy/metadata/album` (`Shared/Metadata/Sources/Metadata/PlaycutMetadataService.swift:99`). The inline `AlbumMetadata` carries no genres/styles, because neither the V2 wire payload nor the `Playcut` model has those fields.

2. **Backend — cache-first sheds genres.** Even when the proxy *is* called, the cache-first `album_metadata` lookup returns only the 10 persisted columns and omits genres/styles **on cache hit** (`apps/backend/services/album-metadata-lookup.service.ts:24-39`, which explicitly documents this and names "persisting them" as the intended follow-up). Genres survive only on a cold-cache LML fall-through.

Net effect: for the steady-state cohort (enriched albums, streaming inline, warm cache), genres never render.

Genres/styles are **not** stored anywhere the read paths can reach cheaply — they are LML-only enrichment. Re-fetching them from LML per request was explicitly rejected (it's the cold-cache cost that triggered the hardening project). The only durable fix is to **persist** them and **carry them inline** in the V2 flowsheet payload, so the detail view shows them with no extra network call and the existing short-circuit stays correct.

## Chosen approach

Genres/styles travel **inline in the V2 flowsheet payload**, sourced from a persisted `album_metadata.genres`/`styles`. Once inline, the iOS short-circuit is *correct* (the inline metadata contains genres), so `PlaycutMetadataService` and its `requestCount == 0` test are untouched. This is the route the codebase already points at (`album-metadata-lookup.service.ts:31` "persisting them is the follow-up path"; [BS#1336](https://github.com/WXYC/Backend-Service/issues/1336)).

## Dependency chain (4 layers)

| Layer | Change | Repo | Ticket |
|---|---|---|---|
| 1 | `album_metadata` gains `genres text[]` / `styles text[]`; enrichment writer UPSERTs them; proxy lookup projects them | Backend-Service | **BS#1336** (already filed; foundation) |
| 2 | V2 flowsheet query selects `album_metadata.genres/styles`; `transformToV2` + `IFSEntryMetadata` emit them as `genres`/`styles` JSON arrays | Backend-Service | NEW, blocked-by BS#1336 |
| 3 | `FlowsheetV2TrackEntry` gains `genres`/`styles` array-of-string; regenerate consumers | wxyc-shared `api.yaml` | NEW, pairs with layer 2 |
| 4 | `FlowsheetEntry`/`Playcut` decode them; `FlowsheetConverter` maps them; `loadMetadata()` seeds inline `AlbumMetadata` | wxyc-ios-64 | NEW, blocked-by layer 2 |

BS#1336 is scoped to the **proxy** path; it covers layer 1 (and incidentally restores genres for proxy callers — V1 / dj-site / V2-empty-streaming) but **not** layers 2–4. The V2-inline path is additive on top of it.

## Layer 2 — Backend V2 flowsheet projection (Backend-Service)

Prereq: BS#1336 has added `genres`/`styles` to `album_metadata` and the enrichment writer populates them.

- `apps/backend/services/flowsheet.service.ts:108-201` — `FSEntryFieldsRaw`: add `genres: album_metadata.genres` and `styles: album_metadata.styles`. Unlike the 10 existing columns there is **no** inline `flowsheet.genres` to COALESCE over, so these are plain `album_metadata.col` selects (matches the `album-metadata-lookup` direct-read rationale at `:62-67`).
- `apps/backend/services/flowsheet.service.ts:386-427` — the three query builders already `leftJoin(album_metadata, …)`; no join change needed.
- `apps/backend/services/flowsheet.service.ts:244` (`transformToIFSEntry`) and `:960-1006` (`transformToV2`) — project `genres`/`styles` onto the track entry alongside `artwork_url` etc.
- `apps/backend/controllers/flowsheet.controller.ts:18-29` — extend `IFSEntryMetadata` with `genres: string[] | null` / `styles: string[] | null`.
- **Tests**: `tests/integration/metadata.spec.js:37-96` ("Metadata Fields in Flowsheet Response") is the template — assert `genres`/`styles` appear on a v2 track entry for an album whose `album_metadata` row carries them, and are `null`/absent when it doesn't.
- Empty-vs-null convention: match whatever BS#1336 lands for the proxy (`populateReleaseMetadata` coerces empty arrays to `undefined`/omitted). Keep the flowsheet shape property-for-property consistent with the proxy.

## Layer 3 — Contract (wxyc-shared `api.yaml`)

- `api.yaml:605-687` — `FlowsheetV2TrackEntry`: add `genres` and `styles` as nullable array-of-string, mirroring the existing `DiscogsRelease`/`DiscogsMatchResult` pattern (`api.yaml:2034-2041`, `:2306-2321`):
  ```yaml
  genres:
    type: array
    nullable: true
    items: { type: string }
    description: Discogs genre tags surfaced on the Playcut Detail card.
  styles:
    type: array
    nullable: true
    items: { type: string }
    description: Discogs style tags (finer-grained than genres).
  ```
- Run `npm run generate` (regenerates TS/Python/Swift/Kotlin). Note: iOS `FlowsheetEntry.swift` is **hand-written**, not generated from this contract, so layer 4 is manual regardless.
- Purely additive optional fields → non-breaking; run `npm run check:breaking` to confirm.

## Layer 4 — iOS decode + render (wxyc-ios-64)

The rendering path **already works** — it just receives empty `tags` today:
- `PlaycutMetadataSection.swift` combines `genres + styles` into `tags` → `GenreTagsView` renders capsules.
- `PlaycutDetailView.swift:70` gating already tests `metadata.album.genres?.isEmpty == false || metadata.album.styles?.isEmpty == false`.

Changes (TDD, smallest first; each is forward-compatible — decodes a new optional field that is simply absent until the backend emits it, so this can land independently of layers 2–3 with no behavior change):
- `Shared/Playlist/Sources/Playlist/V2/FlowsheetEntry.swift:45-63` — add `var genres: [String]? = nil` and `var styles: [String]? = nil` (snake_case-free names map directly to wire keys `genres`/`styles`; no custom `CodingKeys`).
- `Shared/Playlist/Sources/Playlist/PlaylistEntry.swift:144-258` — `Playcut`: add `genres: [String]?` / `styles: [String]?` stored props, init params (defaulted `nil` to preserve call sites), and `CodingKeys` entries.
- `Shared/Playlist/Sources/Playlist/PlaylistEntry.swift:260-297` — **`Playcut` uses a custom `init(from decoder:)`, not synthesized Codable.** Decoding logic must be added explicitly alongside the existing inline-metadata fields: `self.genres = try container.decodeIfPresent([String].self, forKey: .genres)` and the same for `styles`. (Adding `CodingKeys` alone is insufficient — without this the custom decoder never reads them and decode tests fail.)
- `Shared/Playlist/Sources/Playlist/V2/FlowsheetConverter.swift:37-57` — map `entry.genres`/`entry.styles` into the `Playcut(...)` initializer.
- `Shared/Playlist/.../PlaylistStubs.swift` (`Playcut.stub()`, ~`:32-56`) — add nil-defaulted `genres`/`styles` parameters so tests can set them without boilerplate (the V2 fallback tests already lean on this factory).
- `WXYC/iOS/Views/Playlist/Playcut Detail/PlaycutDetailView.swift:147-161` — seed the inline `AlbumMetadata` with `genres: playcut.genres, styles: playcut.styles`. This is the line that makes the short-circuit return genres.
- **Tests**:
  - `FlowsheetConverter` decode test (in the Playlist package's V2 converter test suite): a V2 entry JSON with `genres`/`styles` → `Playcut` carries them.
  - `Playcut` Codable round-trip including genres/styles (Playlist package model tests).
  - Inline-seed path: extend the Metadata package's `PlaycutMetadataServiceV2FallbackTests` (or a sibling) — a `Playcut` stub with genres + an inline streaming URL, fed through `loadMetadata`'s inline construction, yields `metadata.album.genres` populated (guards against a future short-circuit re-drop). If `loadMetadata` itself isn't unit-testable from the view target, assert at the `PlaycutMetadata` inline-construction boundary instead and note the gap.
  - Use WXYC-canonical fixtures (Juana Molina "DOGA" → Rock; Chuquimamani-Condori → Electronic) per `docs/test-fixtures.md`.

## Sequencing / PRs

1. BS#1336 (foundation) — coordinate, not in this plan's PRs.
2. Layer 3 contract PR (wxyc-shared) — small, additive; land early so the wire field is specified.
3. Layer 2 backend PR (Backend-Service) — blocked-by BS#1336 columns + layer 3 contract.
4. Layer 4 iOS PR (wxyc-ios-64) — decode is forward-compatible so *may* land before/parallel to layer 2; full behavior (capsules visible) verified once layer 2 is in prod.

Each PR is well under the 1000-line guidance.

## Governance

This touches the **frozen** [Post-launch service hardening](https://github.com/orgs/WXYC/projects/32) project (`album_metadata` = Epic D; V2 flowsheet shape = critical surface). All new tickets must be added to the project and wired (blocked-by BS#1336). BS#1336 itself is not currently on the board despite being in scope — add it.

## Acceptance

- A V2 flowsheet track entry for an album with persisted genres/styles includes `genres`/`styles` JSON arrays.
- `api.yaml` `FlowsheetV2TrackEntry` declares both fields; consumers regenerate cleanly; `check:breaking` passes.
- iOS `Playcut` decodes them; the Playcut Detail card renders genre/style capsules for a V2 row with streaming inline **and no proxy call** (short-circuit unchanged).
- No change to `PlaycutMetadataService` short-circuit or its `requestCount == 0` test.
