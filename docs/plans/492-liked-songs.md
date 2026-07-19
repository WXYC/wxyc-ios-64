# Liked Songs (#492) — implementation plan

Status: planned 2026-07-18. Supersedes the R3a "artist likes" section of `docs/plans/474-touring-soon-tab.md` (issue #492's body predates this pivot and gets rewritten alongside the final PR).

## Context

Issue #492 was originally specced as on-device **artist** likes. On 2026-07-18 the model was pivoted: listeners like **songs**; the For You shelf (R3b, #493) derives its artist set from the songs they like. The governance gate [BS#1625](https://github.com/WXYC/Backend-Service/issues/1625) resolved **approved** (2026-07-18): `artist_id` (additive, nullable) is live on the V2 flowsheet wire (BS PR #1698, deployed). The wxyc-shared SSOT patch ([wxyc-shared#239](https://github.com/WXYC/wxyc-shared/pull/239), api.yaml 1.19.0) is open awaiting a second approval — the iOS decode is hand-written Codable (no codegen), so iOS work is not technically blocked on it, but it should merge promptly to keep the SSOT ahead of consumers.

Interaction design was settled against a live prototype study: `docs/ideas/artist-likes-interactions.html` (v1 artist-likes rejected; v2 song-likes, VERDICT recorded 2026-07-18).

## Decision record (2026-07-18)

1. **The unit of a like is the song.** Playcuts are gesture sites; there is no artist-like or show-bookmark anywhere in this feature. For You derives `distinct artistId across liked songs`; liked-songs-per-artist is available later as a free affinity weight for R3b ranking.
2. **Song identity = folded(artistName) + folded(songTitle).** Folding is case-, diacritic-, and width-insensitive with whitespace collapsed. Album is deliberately excluded (the single, the LP cut, and a free-text replay dedupe together). `artistId` is an attribute, never part of the key.
3. **Surfaces: playcut row + playcut detail card only.** On the row, the heart **replaces the info-circle** in the trailing slot (study verdict B): same 44pt target, same `.title3` scale; "tap for more" rides on the row tap, which already fires the identical `onSelect`. The detail card gets a heart beside the song title. **Concert-surface hearts are deferred** — their meaning (artist follow vs. show bookmark) is a future ticket, not this one.
4. **Snapshot at like time.** The like stores a lean `LikedSongSnapshot` of the playcut's display fields (title, artist, artistId?, album, label, artwork/streaming URLs) plus `likedAt`, so liked rows and their detail cards render after the play scrolls out of the live feed. Deliberately NOT a raw `Playcut`: that would also serialize `artistBio`, `genres`, `styles`, and the embedded `upcomingShow` — several KB per like that the list never reads. A `toPlaycut()` bridge feeds the detail card. Staleness of snapshotted URLs is accepted for v1.
5. **Heal on observation.** A nil-`artistId` liked song gains its id when any id-bearing playcut with a matching folded artist name is observed (flowsheet ingest). Rationale: a free-text like is otherwise permanently invisible to For You — the filled heart prevents the re-like that would capture the id.
6. **Persistence: a minimal Codable JSON file store** in Application Support behind a small `FileStorage` protocol seam (in-memory double for tests). Every existing layer was considered and rejected for cause: SwiftData (first-in-repo `ModelContainer` cost, not needed at this scale); `DefaultsStorage` (unbounded song snapshots in a launch-loaded plist); and the `Caching` package (`CacheCoordinator`/`Cache`), which is semantically a **cache** — it purges `lifespan == .infinity` entries at init and TTL-expires finite ones, so durable user-curated data stored there is either lost on next launch or silently expires. Likes are canonical data, not re-derivable cache content, so they get a store whose contract is "never evict." The store reads synchronously at init and does atomic synchronous write-through on mutation (payloads are KBs; this eliminates any first-paint unliked-flash or load/toggle race — revisit only if profiling objects).
7. **Browsing: a fourth root tab, "Liked"** (heart icon), between On Tour and Info. Newest-first list; unlike via swipe-left or heart-off; tap reopens the standard playcut detail; deliberate empty state.
8. **Privacy invariants unchanged:** likes never leave the device — no server round-trip, no account, and the analytics event carries no artist or song identity, matching the `OnTourEvents.swift` precedent. `SongLikeToggled` fields: `action` (like/unlike), `surface` (row/detail/liked_tab), and `totalBucket` — the post-toggle store size as a coarse bucket (`0`, `1-9`, `10-49`, `50+`) so habit retention is visible without identity (decided 2026-07-18).
9. **No feature flag.** Ships ungated (decided 2026-07-18): the feature is entirely on-device, a flag would only hide UI while doubling the test matrix, and a broken tab needs an app update regardless. Hearts render on the V1 playlist-API path too — likes there are name-only until healed by a V2 session. R3b's noise-cap flag is a separate, unaffected decision.
10. **Liked-song detail shows no Box Office ticket in v1** (decided 2026-07-18): the snapshot excludes `upcoming_show`, and concert surfacing for liked artists is R3b's job on the On Tour tab. Tab details confirmed: named **"Liked"**, SF Symbol `heart`, third position (Now Playing · On Tour · Liked · Info). Empty state: large heart glyph + headline **"Show some love"** with the small teaching subline "Tap the heart on a song you love." (subline kept unless Jake objects).

## Architecture

### PR A — `artist_id` decode (tiny, lands first)

- `Shared/Playlist/Sources/Playlist/V2/FlowsheetEntry.swift`: add `artist_id: Int?` (decodes absent → nil; forward-compatible like `upcoming_show`'s `TolerantConcert` handling but plain optional suffices).
- `Shared/Playlist/Sources/Playlist/V2/FlowsheetConverter.swift`: map onto a new `Playcut.artistId: Int?` (`PlaylistEntry.swift`), defaulted `nil` in the init so existing call sites and the V1 path compile unchanged.
- `Playcut` has explicit `CodingKeys` and a hand-written `init(from:)`: add `.artistId` to `CodingKeys` and decode it in `init(from:)` so the field survives encode→decode — playlists are disk-cached as encoded `Playcut`s and re-decoded on launch, so without this a cached playcut silently drops `artistId`.
- Tests (PlaylistTests): decode fixture with and without `artist_id`; converter mapping; V1 path leaves it nil; `Playcut` encode→decode round-trip asserting `artistId` survives (cache survival).

### PR B — `Shared/LikedSongs` package (no UI)

New local SwiftPM package mirroring the Concerts package layout (platforms iOS 18.4, products `LikedSongs` + `LikedSongsTesting`, test target with fixtures). Dependency: `Playlist` (for the `Playcut` bridge type). All new files carry the standard header block enforced by `scripts/hooks/header-check.sh` (see `docs/file-headers.md`).

**Mechanical wiring (this repo hardcodes package membership — Concerts is a poor template here because `ConcertsTests` is absent from all three, i.e. CI-invisible):** register `LikedSongsTests` in `WXYC.xctestplan`; add the package to `.github/scripts/affected-tests.sh` (`DEPS`/`TEST_TARGETS`/`SPM_RUNNABLE`/`all_test_plan_targets`) and to `scripts/test-affected.sh`'s `FORCE_FULL` branch specifically (the hardcoded `SPM_AFFECTED` list + matching `SKIP_FLAGS` — there is no DEPS map in that file, and its list is already drifting from `affected-tests.sh`); and in PR C add the `project.pbxproj` package reference **and** app-target product dependency so the app links `LikedSongs` explicitly (per `docs/project-structure.md`; do not rely on transitive linking — that trap is documented on Concerts-via-Playlist).

- `SongKey`: `fold(String)` (`.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))` + whitespace collapse — explicit locale pinned like `PlaylistEntry`'s locale-sensitive string work, so the dedupe key is stable on e.g. Turkish-locale devices) and `key(artist:title:)`.
- `LikedSongSnapshot`: `Codable`, `Equatable` — lean display fields (title, artist, artistId?, album, label, artwork/streaming URLs) + `likedAt: Date` + computed key, with `init(playcut:likedAt:)` and `toPlaycut()` for detail-card reuse. Primary storage shape (not raw `Playcut` — see decision #4).
- `FileStorage` protocol (`load() throws -> Data?` / `save(Data) throws`); `AppSupportFileStorage(filename:)` with atomic writes; `InMemoryFileStorage` in `LikedSongsTesting`. Never-evict contract per decision #6.
- `LikedSongsStore` (`@MainActor @Observable public final class`): `songs` (newest first), `isLiked(artist:title:)`, `toggle(_ playcut: Playcut) -> Bool` (returns liked/unliked for analytics), `heal(from: [Playcut])`, `likedArtistIds: Set<Int>`. Synchronous load on init (corrupt/missing data → empty store, logged, never fatal) so hearts are correct at first paint with no load/toggle race; atomic synchronous write-through on mutation.
- `SongLikeToggled` in `Shared/Analytics` Events via the `@AnalyticsEvent` macro (`action: String`, `surface: String`, `totalBucket: String` — the post-toggle store size bucketed `0`/`1-9`/`10-49`/`50+`; no artist or song identity; privacy note in the header comment like `OnTourEvents.swift`). Bucketing lives in `LikedSongs` (`LikedSongsStore.totalBucket`) so it's unit-tested at the boundaries (0→1, 9→10, 49→50).

TDD order: SongKey folding (parameterized: case, diacritics via Nilüfer Yanya, ALL-CAPS, whitespace, Turkish dotless-i) → toggle insert/remove + dedupe across album variants and free-text replays → heal (stamps id on folded-name match, preserves `likedAt`, skips non-nil rows) → `likedArtistIds` distinct/non-nil → persistence round-trip + corrupt-data recovery → sort order.

### PR C — UI + wiring

- `RootTabView.swift`: add `.liked` to the `Page` enum **and all three of its switches** (`title`, `systemImage`, `accessibilityIdentifier` → `"tab.liked"`), positioned between On Tour and Info; construct the tab via the enum accessors like the existing tabs, not inline literals. Keep `overlaySheet`/`selectedPlaycut` plumbing untouched. Update the tests that pin the tab set: `RootTabPageTests` (hard-asserts `Page.allCases` and the accessibility-id mapping — also refresh its "three tabs" file-header comment and the `"Three tabs in order: …"` test name so the suite doesn't misdescribe itself), `WallpaperUITests` (parameterizes the tab IDs — see the `LikedTabView` bullet for the picker-gesture prerequisite), and `RootTabBarUITests` (refresh its two-destination intent comment; assert the Liked tab is reachable).
- `PlaycutRowView.swift`: replace the info `Button` (`info.circle`) with the heart (outline `heart` / filled `heart.fill`, `.title3`, 44×44, white 80% unliked, theme-red filled, `accessibilityLabel` + pressed state; small pop animation gated on reduced motion). Row tap behavior unchanged. Works identically inside the ticket-row variant.
- Detail-card heart: the title actually renders in `PlaycutHeaderSection.swift` (a separate struct with no store access today), not `PlaycutDetailView.swift`. Add the heart there, fed by an `isLiked`/`toggle` closure pair passed down from `PlaycutDetailView` (which already has `Singletonia` access) — keeps the header section store-agnostic.
- `LikedTabView` (app target): list of `LikedSongSnapshot` rows (artwork via the existing `ArtworkLoader` where resolvable, else placeholder), swipe `Unlike` action + tappable filled heart, newest-first, tap presents the standard playcut detail via `toPlaycut()` through the tab's **own** `@State` + `.overlaySheet` (mirroring `RootTabView`'s pattern — the root's `selectedPlaycut` is `private` and stays untouched), empty state (large heart glyph, headline "Show some love", subline "Tap the heart on a song you love."). Must carry the per-tab conventions every root tab has: `.themePickerGesture(...)`, `.clearTabBarBackground()`, and a `likedTabView` content-surface accessibility identifier — then add `("tab.liked", "likedTabView")` to `WallpaperUITests.pickerTabCases` so the parameterized picker test covers it. Tab badge count optional; skip if it fights the iOS 26 tab bar styling.
- Store instantiation: single instance on `Singletonia` (matching `artworkLoader`'s pattern); healing wired as a `startLikedSongsHealing()`-style subscription to `playlistService.updates()`, the same insertion pattern as `Singletonia.startPlaycutHistory()`/`startSpotlightDonation()`.
- Analytics capture at the toggle sites with the surface string (`row` / `detail` / `liked_tab`).
- Docs in the same PR: rewrite the R3a section of `docs/plans/474-touring-soon-tab.md` to point here (recording the BS#1625 "approved" outcome per the gate's paper trail, the song-like pivot, and the SwiftData reversal); add a `LikedSongs` row to the package table in `docs/architecture.md`; note the `FileStorage` seam in `docs/swift-style.md` as the sanctioned pattern for durable (never-evict) user data vs. `DefaultsStorage`/`Caching` for small prefs and re-derivable caches; package README per repo convention. Study file already carries the verdict.

UI smoke tests per `docs/build-test.md` conventions: four tabs reachable, heart present on a playcut row, Liked tab shows empty state then a liked row after toggling.

## Out of scope (recorded so they don't creep back in)

- Concert-surface hearts (deferred; meaning undecided — future ticket).
- iCloud sync (future: swap the persistence layer; the file store keeps this a data-migration-free swap).
- Name-matching against concerts for For You (R3b matches on ids only; #493 unchanged in shape).
- Any server-side awareness of likes.

## Process checklist

1. PR A → PR B → PR C, each ≤1000 lines, rebase-merged in order (A and B are independent of each other in principle but sequenced to keep `Playcut.artistId` available to B's snapshot tests).
2. Rewrite #492's body to this model when PR C opens (decision record + new acceptance criteria below); comment on #493 that the taste source is now liked songs (derived `likedArtistIds` — same shape it consumes today).
3. Nudge wxyc-shared#239 to merge (SSOT ordering; not a technical blocker).
4. Local checks before every push per repo convention (`docs/build-test.md`).

## Acceptance criteria (supersede #492's)

- Heart on the playcut row (trailing slot, replacing the info-circle) and the detail card; state persists across launches via the file store.
- The same song across plays — linked or free-text, any casing/diacritics/whitespace — is one liked song; hearts on all its visible plays render in sync.
- Liked tab: newest-first browse, unlike via swipe and heart-off, deliberate empty state, row tap opens the standard detail card from the snapshot.
- A name-only like gains its artist id when a linked play of the same folded artist name is observed, without user action.
- `likedArtistIds` is exposed for R3b; no likes data appears in any network request; `SongLikeToggled` carries no artist or song identity.
