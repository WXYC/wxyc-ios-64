# Capturing song / album / artist identity for Likes

## Why

The Likes feature (#492) shipped with a deliberate privacy invariant: the analytics event carries no artist or song identity, and no taste signal ever reaches the server. That decision was made 2026-07-18 and is asserted across roughly two dozen sites in the codebase.

It is now being reversed by product decision (2026-08-21). WXYC wants to know **which songs, albums, and artists listeners like** — a station-level taste signal that the current instrumentation cannot produce at any volume, because the data is never collected.

This plan covers the iOS app only. Android parity is out of scope, tracked in [WXYC/WXYC-Android#40](https://github.com/WXYC/WXYC-Android/issues/40).

## What exists today

`SongLikeToggled` carries three fields — `action` (`like`/`unlike`), `surface` (`row`/`detail`/`liked_tab`), and `totalBucket` (`0`/`1-9`/`10-49`/`50+`). Three call sites emit it: `PlaycutRowView.toggleLike()`, `PlaycutDetailView.toggleLike()`, and `LikedTabView.unlike(_:)`.

The gap is wider than Likes. **No event in the app captures a song title.** `PlaycutDetailViewPresented`, `StreamingLinkTapped`, and `ExternalLinkTapped` each carry `artist` and `album` only. "Capture song/album/artist data" therefore means adding `song_title` to three existing events as well as adding full identity to the like event.

`LikedSongSnapshot` already persists everything needed on device: `songTitle`, `artistName`, `artistId` (nullable, healed from V2 plays), `releaseTitle`, `labelName`, plus artwork and streaming URLs. Nothing new has to be captured at the UI layer — the data is already in hand at every toggle site.

## Decisions

1. **Both sinks, in that order.** PostHog gets identity as event properties (fast, answers "is this interesting at all"). Backend-Service gets a durable, WXYC-owned store (answers "top-liked artists over time", joinable against the catalog). PostHog is not a substitute for the second: its event store is the wrong shape for long-horizon aggregation, and org-wide ingestion was dead 2026-08-05 → 2026-08-18, so it is a lossy record.

2. **Backend-Service stores current like state, not an event log.** A `POST` per toggle would make "top-liked artists" a count of *toggles*, which one indecisive listener can dominate. Storing per-listener current state makes the headline metric `count(distinct listener)` per artist, which is what the question actually asks.

3. **Sync is a full-snapshot idempotent `PUT`, not a per-toggle queue.** `PUT /listeners/me/likes` with the complete snapshot array. This handles three problems with one mechanism: offline toggles, retry after failure, and backfill of likes made before this ships. A per-toggle queue would need its own durable storage, ordering guarantees, and a separate backfill path.

4. **Likes are attributed to the anonymous session user id, and the resulting churn is accepted rather than engineered away.** Deduping requires a listener key; without one, "top-liked artists" cannot distinguish 30 listeners from one listener toggling 30 times. This is the substantive privacy change — the server will hold a per-listener taste profile keyed to an anonymous id, not to a name, email, or account, because the app has none.

   The churn model is known, not an open question. `AuthSession` is a ~30-day refresh credential fronting a ~15-minute JWT, and `MusicShareKitConfiguration` documents re-minting an orphaned anonymous user on a Keychain-miss device (#948). The listener key therefore rotates on reinstall, Keychain loss, and any lapse past the refresh window, and `count(distinct listener)` inflates accordingly. The inflation is bounded and one-directional.

   **Stance: accept it and caveat the metric** rather than persisting a store-local UUID alongside the likes file. A device-scoped identifier that outlives session rotation would be more accurate and *more durable than the thing it replaces* — a worse privacy trade for a metric that only needs approximate distinct counts. Revisit only if observed reinstall churn makes artist rankings unstable.

5. **The local store stays authoritative.** `LikedSongsStore` continues to be a synchronous, on-device, write-through store. The network sync is strictly best-effort and downstream. A failed sync must never block, revert, or delay a heart tap.

6. **Two keys, two purposes — the client and server folds are never required to agree.** They are not the same function and must not be conflated:

   - `SongKey.fold` (`SongKey.swift:29-33`) folds case + diacritic + **width** under `en_US_POSIX` and collapses/trims whitespace.
   - The server's `foldArtistName` (`shared/database/src/fold-artist-name.ts:52`, twin of SQL `wxyc_schema.fold_artist_name`, migration 0134) is NFD → strip U+0300–U+036F → lowercase. No width folding, no whitespace collapsing. Its header warns the twin "MUST stay byte-identical" to the SQL function.

   So: **`songKey` is the client's key, carried on the wire and stored verbatim.** It identifies the like row. The server never recomputes it, and `SongKey.fold` is authoritative for row identity.

   **Artist matching against the catalog uses the server's fold**, applied server-side to the raw `artistName` in the payload. The SQL function stays authoritative for catalog identity — that is what the rest of the library already matches on.

   The payload therefore carries both the client key and the raw, unfolded `artistName`. Consequence to accept: the folded-name fallback will miss on width-variant and multi-space inputs that `SongKey` collapses but `fold_artist_name` does not. That is tolerable because the fallback is best-effort and `artistId` covers the healed path — but it must not be described as "client and server agree on identity," because they do not.

7. **Property names and representations match the three existing identity-bearing events.** The like event emits `artist` / `album` / `song_title`, not `artist_name` / `release_title`, so queries unioning "liked" against "viewed" artists need no `coalesce`.

   `album` is `String` (non-optional), populated `playcut.releaseTitle ?? ""` at the call site, exactly as `PlaycutDetailViewPresented`, `StreamingLinkTapped`, and `ExternalLinkTapped` already do at `PlaycutDetailView.swift:135,151,167,197`. Emitting `""` from three events and omitting the key from a fourth would reintroduce the cross-event divergence this decision exists to prevent. Only `artistId` stays optional-and-omitted, because it has no sibling and absent-vs-unresolved is a real distinction.

## Design

### Phase 1 — PostHog identity (iOS, self-contained)

**Step 1a: put the derivation somewhere a test can reach it.** `toggleLike()` is a `private func` on a SwiftUI `View` (`PlaycutRowView.swift:241`, `PlaycutDetailView.swift:371`). Injecting an `any AnalyticsService` onto the view does **not** make it callable from `WXYCTests` — the method stays unreachable. The repo's working precedent for testing logic in these exact views is a pure static: `LikeHeartButton.shouldCelebrate(from:to:reduceMotion:)`, exercised at `WXYC/iOS/Tests/WXYCTests/LikeHeartButtonTests.swift:19`.

Follow that. Add a pure value-mapping function in `Shared/LikedSongs` that turns a toggle into the event's field values:

```swift
public struct LikeAnalyticsFields: Equatable, Sendable {
    public let action: String      // "like" / "unlike"
    public let songTitle: String
    public let artist: String
    public let album: String       // "" when the playcut has no release title
    public let artistId: Int?
}
```

with a static producing it from a `Playcut` (and a `LikedSongSnapshot` overload for the tab's unlike path). It lives in `LikedSongs`, which already depends on `Playlist`, and is tested in `LikedSongsTests` — SPM-runnable on the macOS host.

**This deliberately does not test "the view called `capture`."** A private method on a SwiftUI view is not reachable, and contorting the view hierarchy to make it so would cost more than it proves. What gets tested is everything that can actually be wrong: like-vs-unlike action, nil `artistId` omission, empty-album coalescing, and fields not being transposed. The views become a mechanical five-line mapping with no branching. This is the same bargain `shouldCelebrate` already strikes.

Analytics must **not** gain a dependency on `LikedSongs` or `Playlist` to host this — its `Package.swift` declares `AnalyticsMacros`, `Logger`, and `PostHog`, and pulling `Playlist` in would put it in every Analytics consumer's graph.

**Step 1b: the event gains identity.** `SongLikeToggled` drops `@AnalyticsEvent` and conforms by hand, exactly as `ErrorEvent` does (`ErrorEvents.swift:18-41`) — the macro expansion emits a flat dictionary literal with no nil handling (`Shared/AnalyticsMacros/Sources/AnalyticsMacrosPlugin/AnalyticsEventMacro.swift:99-115` — note there is a second file of the same name at `Shared/Analytics/Sources/Analytics/AnalyticsEventMacro.swift` holding the `@attached` declaration), so an `Int?` would serialize as an `Optional`-wrapped `Any`.

```swift
public struct SongLikeToggled: AnalyticsEvent {
    public static let name = "song_like_toggled"

    public let action: String
    public let surface: String
    public let totalBucket: String
    public let songTitle: String
    public let artist: String
    public let album: String
    public let artistId: Int?

    public var properties: [String: Any]? {
        var props: [String: Any] = [
            "action": action,
            "surface": surface,
            "total_bucket": totalBucket,
            "song_title": songTitle,
            "artist": artist,
            "album": album,
        ]
        if let artistId { props["artist_id"] = artistId }
        return props
    }

    public init(
        action: String,
        surface: String,
        totalBucket: String,
        songTitle: String,
        artist: String,
        album: String,
        artistId: Int? = nil
    ) {
        self.action = action
        self.surface = surface
        self.totalBucket = totalBucket
        self.songTitle = songTitle
        self.artist = artist
        self.album = album
        self.artistId = artistId
    }
}
```

The explicit `public init` is **required, not stylistic**: the implicit memberwise init is `internal`, and all three call sites live in the `WXYC` app target. The macro-backed version has one today (`LikedSongsEvents.swift:26`), and `ErrorEvent` carries one at `ErrorEvents.swift:44`.

~~Dropping the macro means the event name is no longer derived, so it can silently move.~~ **Corrected during PR 1:** this premise is wrong. `AnalyticsEvent` carries a *protocol-extension* default `name` that snake-cases the type name (`AnalyticsEvent.swift:33-36`), so the name survives dropping the macro either way; the macro only pre-bakes it as a stored `let` instead of recomputing it per capture. The pin is still worth adding, for the reason that actually applies to every event: the name is derived from the **type name**, so a rename of the type silently renames the event. `SongLikeToggled` is absent from `EventNameStabilityTests` today; **add it there first**, and keep the explicit `static let name` on the hand-written conformance so the string is stored rather than recomputed.

**Step 1c:** `PlaycutDetailViewPresented`, `StreamingLinkTapped`, and `ExternalLinkTapped` each gain `songTitle: String`. Note this is a **source-breaking memberwise-init change** at four existing emit sites (`PlaycutDetailView.swift:132,148,164,195`), each of which must pass the title. Their existing `artist`/`album` names and non-optionality stay.

### Phase 2 — Contract (wxyc-shared)

`api.yaml` gains one path and two schemas, following the `x-wxyc-service: backend-service` convention used by `/request` and `/concerts`:

- `PUT /listeners/me/likes` — request `ListenerLikesSnapshot` (`{ likes: LikedSongRef[] }`), response `ListenerLikesSyncResponse` (`{ accepted: number, resolved: number }`).
- `LikedSongRef` — `{ songKey, songTitle, artistName, releaseTitle?, artistId?, likedAt }`.

`songKey` is required and carries the client's `SongKey.key` output per Decision #6. `artistName` is the **raw, unfolded** name — the server folds it itself for catalog matching.

The SSOT patch merges before its consumers, per org convention.

### Phase 3 — Backend-Service

- Table `listener_likes`: `(anon_user_id, song_key)` primary key, plus `artist_name`, `song_title`, `release_title`, `artist_id` (nullable FK to `artists.id`), `liked_at`, `synced_at`.
- `PUT /listeners/me/likes` — authenticated (anonymous session bearer), replaces the caller's full set transactionally: upsert everything in the payload, delete the caller's rows absent from it.
- Artist resolution: trust `artist_id` when supplied; otherwise match `fold_artist_name(artist_name)` against `artists`, leaving null on miss. Never fail the write on an unresolved artist.
- Rate limit per session — a full-snapshot `PUT` is cheap but unbounded in frequency without one.
- **Retention: build the sweeper. It does not exist.** There is no anonymous-session or orphaned-user pruning in Backend-Service today — `jobs/` holds only `flowsheet-ghost-row-sweep` and backfills, and `shared/authentication/src/` has no prune path. Anonymous users are plain Better Auth rows (`shared/database/src/schema.ts:62`, `is_anonymous`) with nothing reaping them; 147 orphans were cleaned by hand in April 2026.

  Scope a `listener_likes` sweeper into Phase 3: prune rows whose `anon_user_id` has no `auth_session` newer than the refresh window. This is bounded and specific to the table this plan adds. The broader `auth_user`/`auth_session` growth problem stays out of scope and unfixed — note it, do not silently inherit it. Without the sweeper, `listener_likes` grows one row per like per orphaned reinstall, forever.

### Phase 4 — iOS sync client

**Step 4a: catch the contract pin up first, as its own PR.** `wxyc-shared/api.yaml` is already at `1.42.0`; `Shared/WXYCAPIModels/contract-version.json` pins `1.36.0` / sha `c804de3b`. Regenerating as part of the likes PR would pull six minor versions of unrelated model changes into that diff, and `.github/workflows/verify-api-types.yml` would hold the PR to all of it. Land a standalone regen against current `main` first, so the likes PR's diff is only the likes types.

Then bump to the Phase 2 version and regenerate per `docs/code-generation.md`: `LikedSongRef` and `ListenerLikesSnapshot` come from `WXYCAPIModels`. No hand-written twin — that is the drift hazard #915 fixed for `AppConfig` and #945 still tracks for `AppSecrets`. The V2-flowsheet hand-written decoder is a documented exception under a parity-test guard; nothing here justifies invoking it.

**Step 4b: the sync service.** `LikesSyncService` lives in `Shared/LikedSongs`, which **must add a `WXYCAPIModels` dependency** — it currently declares only `Core`, `Playlist`, `Logger`. See `Shared/Metadata/Package.swift:13` for the pattern.

`WXYCProxyClient` exposes only `get` (`WXYCProxyClient.swift:75`). The body-carrying authed primitive underneath both it and `MusicShareKit.RequestService.sendRequest` is `URLSession.authedData` (`URLSession+AuthedRequest.swift:53`), which already handles 401-reauthenticate-and-retry-once. Add a body method to `WXYCProxyClient` targeting it rather than copying `RequestService`.

`LikedSongs` is on `SPM_RUNNABLE` (`.github/scripts/affected-tests.sh:70`), so `LikesSyncService` tests must pass under `swift test` on the macOS host per `scripts/verify-spm-parity.sh`. `URLProtocol` stubs and `CoreTesting`'s token-provider doubles are fine; simulator-only APIs are not.

`LikedSongsStore` is `@MainActor @Observable`, so the debounced sync must hop off the main actor before doing network work.

**Observation:** the store exposes no delegate or stream and `persist()` is `private`, so "debounced after any store mutation" needs a stated mechanism. Use `Observations` over the store's `songs`, per `docs/swift-style.md`'s preference for `Observations`/`AsyncStream` over closures. Do not add a delegate.

**Dirty-flag home:** `LikedSongsStore` persists through `Core.FileStorage`, a single-blob `load()`/`save()` byte store with no room for a sidecar. Add `Caching` to `LikedSongs` and persist the flag through `DefaultsStorage`, the repo's documented persistence injection. The edge is cheap — `Caching` depends on exactly `Core` + `Logger`, so it drags no new transitive weight (notably no PostHog). This is a **second** package-manifest addition alongside `WXYCAPIModels`.

**Construction site:** every existing network client here takes an optional `SessionTokenProvider` at init from the app layer (`ConcertsFetcher.swift:50`, `PlaycutMetadataService.swift:109`, `DiscogsEntityResolver.swift:49`). `LikesSyncService` follows that shape and is constructed in `Singletonia`. Pass the `tokenProvider` itself — do **not** eagerly capture `MusicShareKit.authService`, which is nil during `Singletonia` construction.

Failures log and set dirty — they never surface UI and never touch store state.

New Swift files need the standard header comment; `scripts/hooks/header-check.sh` enforces it pre-commit.

## Invariant and documentation updates

The invariant is asserted far more widely than the Likes feature itself, and the sites break at **different phases**. Phase 1 falsifies the analytics claims; the On Tour / Spotlight claims stay true until Phase 4 actually sends data to a server.

**Breaks at Phase 1** (identity enters analytics):

| Site | What it says |
|---|---|
| `Shared/Analytics/Sources/Analytics/Events/LikedSongsEvents.swift:6` | "no artist or song identity" |
| `Shared/LikedSongs/Sources/LikedSongs/LikedSongsStore.swift:110` | "volume without identity, per the privacy invariant" |
| `Shared/LikedSongs/README.md:3` | "analytics carry no artist or song identity" — **the analytics clause only**; see Phase 4 for the rest of this same line |
| `WXYC/iOS/Views/Liked/LikedTabView.swift:9` | File header — distinct from the call-site comment below |
| `WXYC/iOS/Views/Liked/LikedTabView.swift:170` | Call-site doc comment |
| `WXYC/iOS/Views/Playlist/Playcut Detail/PlaycutDetailView.swift:369` | Call-site doc comment |
| `WXYC/iOS/Views/Playlist/Playcut Detail/PlaycutRowView.swift:238` | Call-site doc comment |
| `docs/plans/492-liked-songs.md:20, 43, 79` | Invariant #8, the `SongLikeToggled` spec, the acceptance criterion |

**Breaks at Phase 4** (taste signal reaches the server). These need **narrowing to the claim that still holds**, not deletion — the On Tour shelf's intersection genuinely does stay on-device, and its shelf-impression analytics genuinely do stay identity-free. What stops being true is only the unqualified "no taste signal ever reaches the server":

| Site |
|---|
| `Shared/Concerts/Sources/Concerts/ForYouShelf.swift:21` and `:99` |
| `Shared/Concerts/Sources/Concerts/Concert.swift:208` |
| `Shared/AppServices/Sources/AppServices/ConcertSpotlightDonationService.swift:72` |
| `Shared/AppServices/Sources/AppServices/ConcertSpotlightWindowObserver.swift:63` |
| `Shared/Intents/Sources/Intents/ToursNearMeQuery.swift:14` |
| `WXYC/iOS/Views/OnTour/ForYouShelfView.swift:13` |
| `WXYC/iOS/Intents.swift:216` |
| `Shared/Analytics/Sources/Analytics/Events/OnTourEvents.swift:55` |
| `Shared/LikedSongs/README.md:3` — the **device-boundary clause** ("Likes never leave the device — no server round-trip, no account") on the same line PR 1 already touched. The package's front page must also describe the new sync service. |
| `docs/ideas/spotlight-on-tour-entities.md:84` — frames it as a repeated hard invariant |

Regenerate this inventory before each PR rather than trusting the table:

```
grep -rn "no artist or song identity\|no artist identity\|no artist ids\|taste signal\|without identity\|never leave the device" --include="*.swift" --include="*.md" Shared/ WXYC/ docs/
```

The first three alternations are all needed and are not redundant: `docs/plans/474-touring-soon-tab.md` phrases the same invariant as "carry no artist identity for likes/shelf events" (:151) and "carry no artist ids" (:180), and the original two-phrase grep matched **neither**. PR 1 found those sites only in review. Widen this before trusting a clean grep to mean there is nothing left to amend.

`docs/plans/492-liked-songs.md` is a shipped plan and should not be rewritten as though the original decision never happened. Add a dated amendment recording the 2026-08-21 reversal and pointing here.

## Out of scope

- **Android.** No Likes feature exists there at all. Tracked in [WXYC/WXYC-Android#40](https://github.com/WXYC/WXYC-Android/issues/40).
- **watchOS / tvOS / CarPlay.** No like affordance on those surfaces.
- **Backfill of historical likes.** Impossible — never collected. Existing on-device likes sync on first launch after Phase 4.
- **`auth_user` / `auth_session` pruning.** Real and unfixed, but pre-existing and broader than this work. Phase 3 sweeps only `listener_likes`.
- **The dashboard.** The PostHog tiles built 2026-08-21 stay as-is until Phase 1 accumulates data worth charting.

## Risks

- **App Store privacy declaration.** Music preference is a listener profile. The App Privacy answers live in App Store Connect, not this repo — there is no `.xcprivacy` manifest here at all. **Review before the first build carrying Phase 1 ships**, not Phase 4: identity-bearing taste data leaves the device at Phase 1, to a third-party processor (PostHog), keyed to its `distinct_id`. Phase 4 changes who else receives it, not whether it is collected. This is the one item that blocks a release rather than a PR, and it now blocks the *next* release rather than a distant one.
- **Phase 1 without Phase 3 is the worst outcome.** PostHog would hold identity-bearing like events keyed to `person_id` while the durable store that justified breaking the invariant does not exist. Either commit to Phase 3 or do not start.
- **Distinct-listener inflation.** Per Decision #4, accepted and caveated. Any dashboard tile built on `count(distinct listener)` must carry the caveat in its description.
- **`artist_id` is asymmetric between the like and the unlike path, and is not being fixed here.** The row/detail sites read `playcut.artistId`, which is nil for free-text and V1 plays; the Liked-tab unlike path reads `snapshot.artistId`, which `LikedSongsStore.heal(from:)` may have stamped *after* the like was recorded. So the same song can emit a like with `artist_id` absent and a later unlike with it present. Consequence: netting likes minus unlikes on `artist_id` can go negative for an artist, and distinct-artist counts over like events under-count relative to unlike events. This is tolerable precisely because Decision #2 already rules out toggle-netting as the metric — Phase 3's durable per-listener current-state store is the sanctioned answer to "top-liked artists". Do not build a PostHog tile that nets toggles. Closing the gap would need a pre-toggle store lookup at two view sites that are deliberately untestable, which is the branching the Phase 1 testability bargain exists to keep out of the views.
- **Folded-name fallback misses.** Per Decision #6, the server's fold is narrower than the client's. Width-variant and multi-space artist names will fail the catalog match and land `artist_id` null.

## Testing

TDD throughout, per repo standard.

- `EventNameStabilityTests` covers `song_like_toggled` **before** the macro is dropped.
- Hand-written `properties`: nil `artistId` omits its key; populated round-trips; `album` always present.
- `LikeAnalyticsFields` derivation (`LikedSongsTests`, host-runnable): like-vs-unlike action, nil `artistId`, empty-album coalescing, fields not transposed.
- `LikesSyncService` (`LikedSongsTests`, host-runnable under `verify-spm-parity.sh`): snapshot serialization including `songKey`; failure leaves the store untouched and sets dirty; dirty triggers retry on foreground; the sync hops off `@MainActor`.
- Backend-Service: full-replace semantics (rows absent from the payload are deleted), `artist_id` trusted when supplied, `fold_artist_name` fallback, unresolved artist does not fail the write, sweeper prunes only rows past the refresh window.
- Fixtures use WXYC-canonical tracks (Juana Molina, Jessica Pratt, Chuquimamani-Condori), not generic placeholders. The diacritic names (Nilüfer Yanya, Hermanos Gutiérrez) are the ones that exercise the fold divergence.

## Delivery

Five PRs across three repos. Conventional commits with scopes, matching repo history (`feat(sentry):`, `fix(ios):`), and `feat/` branch prefixes. **This worktree (`.worktrees/likes-identity-capture`, branch `likes-identity-capture`) becomes PR 1** — rename the branch to `feat/like-analytics-identity` and the worktree directory to match. PRs 0 and 4 get their own worktrees; do not stack them here.

| # | Repo | Branch | Contents |
|---|---|---|---|
| 0 | wxyc-ios-64 | `chore/contract-pin-catchup` | Regen `WXYCAPIModels` against current `main` (1.36.0 → 1.42.0). Independent of this work. |
| 1 | wxyc-ios-64 | `feat/like-analytics-identity` | `LikeAnalyticsFields`, event identity, name-stability test, Phase 1 invariant docs |
| 2 | wxyc-shared | `feat/listener-likes-contract` | `api.yaml` path + schemas |
| 3 | Backend-Service | `feat/listener-likes` | Table, endpoint, resolution, rate limit, sweeper |
| 4 | wxyc-ios-64 | `feat/likes-sync` | Pin bump to Phase 2, sync client, dirty flag, Phase 4 invariant narrowing |

**Landing gate, not a suggestion:** 2 merges before 3, and 3 deploys before 4 ships. PR 0 can land any time and should land first to keep PR 4's diff readable. PR 1 is independently valuable and independently revertible.

## Related

- #492 — the original Likes feature and the invariant this reverses.
- #493 — the For You shelf, whose local-intersection invariant is narrowed but not removed.
- [WXYC/WXYC-Android#40](https://github.com/WXYC/WXYC-Android/issues/40) — Android Likes parity, filed 2026-08-21 as future work. Built against the post-reversal design so the identity work is not done twice.
