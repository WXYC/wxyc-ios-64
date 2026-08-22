# LikedSongs

On-device liked-songs store for the WXYC app (#492). Listeners heart playcuts; the For You shelf (#493) derives its taste signal from the artists of the songs they like. The liked-songs store never leaves the device — no server round-trip, no account. The *analytics* do: PostHog events carry song/artist/album identity as of the 2026-08-21 product reversal (`SongLikeToggled`; see `docs/plans/likes-identity-capture.md`) — a durable server-side taste store is a later phase of that plan.

## Model

- **The unit of a like is the song.** A liked song's identity is `SongKey.key(artist:title:)` — case/diacritic/width-folded, whitespace-collapsed, album deliberately excluded — so the linked play, the ALL-CAPS free-text replay, and the single vs. LP cut dedupe to one row. The catalog `artistId` is an attribute, never part of the key.
- **`LikedSongSnapshot`** is a lean snapshot of the playcut's display fields taken at like time (not a raw `Playcut` — no bio/genres/styles/embedded show). `toPlaycut()` bridges back for the standard detail card.
- **Heal on observation:** `LikedSongsStore.heal(from:)` stamps artist ids onto nil-id rows when id-bearing plays of the same folded artist name are observed, making free-text likes eligible for For You matching.
- **`likedArtistIds`** is the For You projection: distinct non-nil artist ids (the `artists.id` keyspace shared with `Concert.headliningArtistId`).
- **`LikeAnalyticsFields`** is the pure toggle -> analytics-field mapping consumed by `SongLikeToggled` (in `Analytics`, which this package does not depend on): `action`, `songTitle`, `artist`, `album` (`""` when there's no release title), and `artistId`. One static derives it — `make(from: some LikableSong, liked: Bool)` — over **`LikableSong`**, a local refinement of `Playlist`'s `SongDisplayable` that adds `artistId`, conformed by both `Playcut` (the row/detail toggle sites) and `LikedSongSnapshot` (the Liked tab's unlike path).

## Persistence

Codable JSON through the `FileStorage` seam — `AppSupportFileStorage` in production, `InMemoryFileStorage` (in `CoreTesting`) in tests. Both live in `Core` (hoisted there in WXYC/wxyc-ios-64#557, which also folded in `Concerts`' identical copy), since the seam is a generic byte-file abstraction with no domain specifics; `LikedSongs` consumes it like any other `Core` dependency. Synchronous load at init and atomic write-through on mutation: heart state is correct at first paint, no load/toggle race, and the contract is **never evict**. Deliberately not the `Caching` package (`CacheCoordinator` purges infinite-lifespan entries at init and TTL-expires the rest — right for caches, data loss for user-curated likes) and not `DefaultsStorage` (unbounded snapshots in a launch-loaded plist). See `docs/plans/492-liked-songs.md` decision #6.

## Testing

`swift test --package-path Shared/LikedSongs` (host-runnable; registered in `WXYC.xctestplan` and both affected-tests scripts). `CoreTesting` ships `InMemoryFileStorage`; tests inject a manual clock to control `likedAt` ordering.
