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

1. **Both sinks, in that order.** PostHog gets identity as event properties (fast, answers "is this interesting at all"). Backend-Service gets a durable, WXYC-owned tally (answers "top-liked songs over time", joinable against the catalog). PostHog is not a substitute for the second: its event store is the wrong shape for long-horizon aggregation, and org-wide ingestion was dead 2026-08-05 → 2026-08-18, so it is a lossy record.

   **On PostHog and anonymity (settled 2026-08-21).** The app never calls `identify()`, so no name, email, or account is ever attached to a PostHog person — verified, and the reason Phase 1 ships with song identity. The one property to stay aware of: events still carry a stable per-device `distinct_id` that resolves to a `person_id`, and that field is queryable (it is what produced the "31 listeners liked something" figure on the 2026-08-21 dashboard). PostHog is therefore anonymous but not un-groupable, which is precisely why the Backend-Service side — the durable, WXYC-owned copy — holds no listener key at all.

2. **Backend-Service stores aggregate counters, not per-listener state.** *(Revised 2026-08-21 — this decision previously said the opposite.)* The server keeps a like tally per `song_key` and nothing else: no per-listener row, no snapshot, no event log. Nothing it persists can be attributed back to a device, a session, or a person.

   The original design stored per-listener current state so the headline metric could be `count(distinct listener)` per artist. That is given up. WXYC is not in the business of holding listener taste data, anonymous or otherwise, and a pseudonymous per-device profile is exactly the thing being refused — not a lesser version of it.

3. **Deltas, fire-and-forget, explicitly non-idempotent.** `POST /likes/tally` carries a batch of `+1` / `-1` counter deltas. Retries double-count, drops are lost, counters drift, and a tally measures like **actions**, not distinct listeners — distinct-listener counts are not derivable from this data by design.

   These are accepted costs, not defects awaiting a fix, and the contract says so in the endpoint description so a future implementer does not "correct" them by reintroducing a listener key. In particular the contract forbids clients from queueing, persisting, or retrying deltas: a durable pending-delta queue is per-listener state by another name.

4. **The bearer token authenticates but is never persisted.** The anonymous-session bearer still gates the endpoint for rate limiting and abuse control. The contract states that the authenticated identity MUST NOT be persisted, logged alongside the deltas, or used to key anything the endpoint writes. Session-id churn — the ~30-day refresh window, Keychain-miss re-mints — is now irrelevant, because no session identifier is stored at all.

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

`api.yaml` gains one path and three schemas, following the `x-wxyc-service: backend-service` convention used by `/request` and `/concerts`:

- `POST /likes/tally` — request `SongLikeTallyRequest` (`{ deltas: SongLikeDelta[] }`), response `SongLikeTallyResponse` (`{ applied, resolved }`).
- `SongLikeDelta` — `{ song_key, song_title, artist_name, release_title?, artist_id?, delta }` where `delta` is `+1` or `-1`.

Field names are snake_case, matching the file's existing wire convention (`AlbumSearchResult`, `Concert`), not the camelCase of the Swift models. `song_key` is required and carries the client's `SongKey.key` output per Decision #6; `artist_name` is the **raw, unfolded** name — the server folds it itself.

**Shipped** as [wxyc-shared#389](https://github.com/WXYC/wxyc-shared/pull/389), version 1.44.0, additive-only.

### Phase 3 — Backend-Service

Substantially smaller than the original per-listener design.

- Table `song_like_tallies`: `song_key` primary key, plus `song_title`, `artist_name`, `release_title`, `artist_id` (nullable FK to `artists.id`), `like_count`, `first_seen`, `last_seen`. No listener column exists, and none may be added.
- `POST /likes/tally` — authenticated (anonymous session bearer, for rate limiting only), applies each delta to `like_count`, **clamped at zero**. The bearer identity is never persisted or logged alongside the deltas.
- Artist resolution: trust `artist_id` when supplied; otherwise match `fold_artist_name(artist_name)` against `artists`, leaving null on miss. Never fail the write on an unresolved artist.
- **Never clear a resolved `artist_id` from a delta that lacks one.** Row/detail toggles read `playcut.artistId` (nil for free-text and V1 plays) while the Liked tab reads the possibly-healed `snapshot.artistId`, so a `-1` can legitimately arrive with a nil `artist_id` for a song whose `+1` carried a resolved one. Treat `artist_id` as monotonically resolving.
- Rate limit per session.
- **No sweeper, and no retention policy.** There are no per-listener rows to prune — the reason one was needed is gone. (The pre-existing `auth_user` / `auth_session` growth problem is untouched and still real; it was always out of scope. See #981's sibling discussion.)

### Phase 4 — iOS tally client

Much smaller than the original sync client, because there is no per-listener state to maintain on either end.

**Step 4a: catch the contract pin up first, as its own PR.** Blocked on #981 — `scripts/regenerate-api-types.sh` does not pin the OpenAPI generator version, so regeneration is currently non-deterministic and fails outright where node cannot reach Maven Central. Resolve that before either pin bump.

Then bump to the Phase 2 version and regenerate per `docs/code-generation.md`: `SongLikeDelta` and `SongLikeTallyRequest` come from `WXYCAPIModels`. No hand-written twin — that is the drift hazard #915 fixed for `AppConfig` and #945 still tracks for `AppSecrets`.

**Step 4b: the tally client.** `LikeTallyReporter` lives in `Shared/LikedSongs`, which **must add a `WXYCAPIModels` dependency** — it currently declares only `Core`, `Playlist`, `Logger`. See `Shared/Metadata/Package.swift:13` for the pattern. It does **not** need `Caching`: there is no dirty flag, because there is nothing to reconcile.

`WXYCProxyClient` exposes only `get` (`WXYCProxyClient.swift:75`). The body-carrying authed primitive underneath both it and `MusicShareKit.RequestService.sendRequest` is `URLSession.authedData` (`URLSession+AuthedRequest.swift:53`). Add a body method to `WXYCProxyClient` targeting it rather than copying `RequestService`.

**Fire-and-forget, and that is contractual.** On toggle, post a single delta. On failure: log and drop. **Do not queue, do not persist a pending list, do not retry** — the endpoint description forbids it, because a durable pending-delta queue is per-listener state by another name. `LikedSongsStore` is `@MainActor @Observable`, so the post must hop off the main actor.

**One-time adoption batch.** The first launch after this ships submits the likes already on the device as a single batch of `+1` deltas. Guard it with a persisted "already submitted" flag so an app relaunch does not re-submit — note this flag records *that* a submission happened, never *what* was in it. A reinstall re-submits and double-counts; accepted per Decision #3.

`LikedSongs` is on `SPM_RUNNABLE` (`.github/scripts/affected-tests.sh:70`), so tests must pass under `swift test` on the macOS host per `scripts/verify-spm-parity.sh`. `URLProtocol` stubs and `CoreTesting`'s token-provider doubles are fine; simulator-only APIs are not.

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
- **Backfill of historical likes.** Impossible — never collected. Likes already on a device are submitted once as a batch of `+1` deltas on the first launch after Phase 4, which is as far back as the record can go.
- **`auth_user` / `auth_session` pruning.** Real and unfixed, but pre-existing and broader than this work. Phase 3 no longer sweeps anything — the aggregate-only design creates no per-listener rows to prune.
- **The dashboard.** The PostHog tiles built 2026-08-21 stay as-is until Phase 1 accumulates data worth charting.

## Risks

- **App Store privacy declaration.** Music preference is a listener profile. The App Privacy answers live in App Store Connect, not this repo — there is no `.xcprivacy` manifest here at all. **Review before the first build carrying Phase 1 ships**, not Phase 4: identity-bearing taste data leaves the device at Phase 1, to a third-party processor (PostHog), keyed to its `distinct_id`. Phase 4 changes who else receives it, not whether it is collected. This is the one item that blocks a release rather than a PR, and it now blocks the *next* release rather than a distant one.
- **Phase 1 without Phase 3 is the worst outcome.** PostHog would hold identity-bearing like events keyed to `person_id` while the durable store that justified breaking the invariant does not exist. Either commit to Phase 3 or do not start.
- **Tally drift.** Per Decision #3, accepted. Counters double-count on retry and lose dropped deltas, so they measure relative popularity, not exact counts. Any dashboard tile built on them must say so in its description, and none may claim a distinct-listener figure — that number is not derivable from this data.
- **Backend tallies and PostHog will not agree.** Two independent lossy paths from the same gesture: PostHog drops events during ingestion outages, the tally drops deltas on network failure. Neither is a reconciliation target for the other.
- **`artist_id` is asymmetric between the like and the unlike path, and is not being fixed here.** The row/detail sites read `playcut.artistId`, which is nil for free-text and V1 plays; the Liked-tab unlike path reads `snapshot.artistId`, which `LikedSongsStore.heal(from:)` may have stamped *after* the like was recorded. So the same song can emit a like with `artist_id` absent and a later unlike with it present. Consequence: netting likes minus unlikes on `artist_id` can go negative for an artist, and distinct-artist counts over like events under-count relative to unlike events. This is tolerable precisely because Decision #2 already rules out toggle-netting as the metric — Phase 3's durable per-listener current-state store is the sanctioned answer to "top-liked artists". Do not build a PostHog tile that nets toggles. Closing the gap would need a pre-toggle store lookup at two view sites that are deliberately untestable, which is the branching the Phase 1 testability bargain exists to keep out of the views.
- **Folded-name fallback misses.** Per Decision #6, the server's fold is narrower than the client's. Width-variant and multi-space artist names will fail the catalog match and land `artist_id` null.

## Testing

TDD throughout, per repo standard.

- `EventNameStabilityTests` covers `song_like_toggled` **before** the macro is dropped.
- Hand-written `properties`: nil `artistId` omits its key; populated round-trips; `album` always present.
- `LikeAnalyticsFields` derivation (`LikedSongsTests`, host-runnable): like-vs-unlike action, nil `artistId`, empty-album coalescing, fields not transposed.
- `LikeTallyReporter` (`LikedSongsTests`, host-runnable under `verify-spm-parity.sh`): delta serialization including `song_key`; a failed post leaves the store untouched and is **not** retried or queued; the post hops off `@MainActor`; the adoption batch submits once and not again on relaunch.
- Backend-Service: `+1` / `-1` apply to the right `song_key`; `like_count` clamps at zero; `artist_id` trusted when supplied; `fold_artist_name` fallback; unresolved artist does not fail the write; **a delta with a nil `artist_id` never clears a previously resolved one**; no request path writes any listener identifier.
- Fixtures use WXYC-canonical tracks (Juana Molina, Jessica Pratt, Chuquimamani-Condori), not generic placeholders. The diacritic names (Nilüfer Yanya, Hermanos Gutiérrez) are the ones that exercise the fold divergence.

## Delivery

Five PRs across three repos. Conventional commits with scopes, matching repo history (`feat(sentry):`, `fix(ios):`), and `feat/` branch prefixes. **This worktree (`.worktrees/likes-identity-capture`, branch `likes-identity-capture`) becomes PR 1** — rename the branch to `feat/like-analytics-identity` and the worktree directory to match. PRs 0 and 4 get their own worktrees; do not stack them here.

| # | Repo | Branch | Contents |
|---|---|---|---|
| 0 | wxyc-ios-64 | `chore/contract-pin-catchup` | Regen `WXYCAPIModels` against current `main`. **Blocked on #981** (generator version unpinned). |
| 1 | wxyc-ios-64 | `feat/like-analytics-identity` | `LikeAnalyticsFields`, event identity, name-stability test, Phase 1 invariant docs. **Open as #980.** |
| 2 | wxyc-shared | `feat/listener-likes-contract` | `api.yaml` path + schemas. **Open as wxyc-shared#389.** |
| 3 | Backend-Service | `feat/song-like-tallies` | Counters table, endpoint, artist resolution, rate limit. No sweeper. |
| 4 | wxyc-ios-64 | `feat/likes-tally` | Pin bump, fire-and-forget tally client, adoption batch, Phase 4 invariant narrowing |

**Landing gate, not a suggestion:** 2 merges before 3, and 3 deploys before 4 ships. PR 0 can land any time and should land first to keep PR 4's diff readable. PR 1 is independently valuable and independently revertible.

## Related

- #492 — the original Likes feature and the invariant this reverses.
- #493 — the For You shelf, whose local-intersection invariant is narrowed but not removed.
- [WXYC/WXYC-Android#40](https://github.com/WXYC/WXYC-Android/issues/40) — Android Likes parity, filed 2026-08-21 as future work. Built against the post-reversal design so the identity work is not done twice.
