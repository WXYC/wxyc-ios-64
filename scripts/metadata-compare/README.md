# metadata-compare

CLI tool that fetches the live WXYC playlist via both metadata paths the iOS app uses and emits a side-by-side JSON diff so we can audit which fields agree, which drift, and which are missing on each side.

## Why this exists

The iOS app has two ways to obtain playcut metadata (label, release year, Discogs/streaming links, artist bio + Wikipedia URL):

- **v1 path** — `PlaylistDataSourceV1` fetches the tubafrenzy `recentEntries` payload, which carries *only* basic playcut fields (artist, song, release, label). The detail view then calls `PlaycutMetadataService.fetchMetadata(for:)` per playcut, which hits `api.wxyc.org/proxy/metadata/album` + `/proxy/metadata/artist` on demand.
- **v2 path** — `PlaylistDataSourceV2` fetches `api.wxyc.org/flowsheet`, where every metadata field is already inline on each entry (enriched by Backend-Service's pipeline at flowsheet-row creation time). `FlowsheetConverter` maps those into `Playcut`. The detail view short-circuits `PlaycutMetadataService` entirely (`Playcut.hasV2Metadata == true`).

In production we've observed that the two paths produce visibly different metadata for the same playcut. This tool quantifies that divergence.

## How it works

1. Anonymous auth (mirrors `MusicShareKit.AuthenticationService`'s sign-in + JWT exchange — no Keychain, ephemeral session).
2. Fetch `http://wxyc.info/playlists/recentEntries?v=2&n=<N>` directly. (Bypasses `PlaylistDataSourceV1` so we can vary `n`.)
3. Fetch `https://api.wxyc.org/flowsheet?limit=<N>` directly. (Bypasses `PlaylistDataSourceV2` for the same reason.)
4. For each v1 playcut, project it into a public `Playlist.Playcut` and call `PlaycutMetadataService.fetchMetadata(for:)`. This exercises the real iOS-app resolution path; the cold-cache run mirrors what happens the first time a user opens the detail sheet on a fresh install.
5. v2 metadata is pulled inline from the flowsheet response (exactly what `FlowsheetConverter` would emit on Playcut).
6. Join v1 ↔ v2 by normalized `(artist, song)` — *not* `(artist, song, release, label)`, because release/label themselves drift between the two paths and including them would split legitimate matches into paired "v1-only" / "v2-only" entries.
7. Classify each per-field diff as either **presence drift** (one side has a value, the other has nil) or **value drift** (both have a value but they disagree). Two nils agree.
8. Emit a single JSON report with both per-row detail and aggregate counts per field.

## Build & run

```sh
cd scripts/metadata-compare
swift build
.build/debug/metadata-compare -n 150 -o /tmp/report.json
```

Flags:

| flag | default | meaning |
|---|---|---|
| `-n N` | 50 | window size — passed as `?n=N` to v1 and `?limit=N` to v2 |
| `-o PATH` | `metadata-compare.json` | output file (the report goes to a file, not stdout — Logger's destination spams stdout and would corrupt the JSON) |

## Findings (snapshot: 2026-05-23 21:00 PT, n=150, 110 matched playcuts)

**54 of 110 matched playcuts (49%) had at least one metadata field disagree between v1 and v2.**

### 1. Presence drift — direction is always the same: v1 has the field, v2 has nil

| field | v1 has, v2 missing | v2 has, v1 missing |
|---|---|---|
| spotifyURL | 16 | 0 |
| discogsURL | 16 | 0 |
| releaseYear | 13 | 0 |
| artworkURL | 12 | 0 |
| appleMusicURL | 11 | 0 |
| label | 4 | 0 |
| artistBio | 3 | 0 |
| artistWikipediaURL | 1 | 0 |

There's never a case where v2 has a field that v1 doesn't. v2's inline metadata is structurally less complete than what v1's `PlaycutMetadataService` resolves on demand.

Worst offenders — 16 rows are missing 3+ enriched fields from v2. Examples:

- *Public Image Ltd — The Order of Death*: missing `releaseYear, discogsURL, artworkURL, spotifyURL, appleMusicURL, artistWikipediaURL, artistBio` on v2.
- *Cormac McCarthy — Waltz with the Captain's Daughter*: missing `releaseYear, discogsURL, artworkURL, spotifyURL, appleMusicURL, artistBio` on v2.
- *Stonie Blue — Heaven*: missing `label, releaseYear, discogsURL, artworkURL, spotifyURL, appleMusicURL` on v2.

### 2. Value drift — both sides have a value but they disagree

| field | rows differing |
|---|---|
| label | 48 / 110 (44%) |
| bandcampURL | 20 |
| soundcloudURL | 18 |
| youtubeMusicURL | 18 |
| appleMusicURL | 3 |
| artworkURL | 1 |
| artistBio | 1 |

#### Label (48 rows)

v1 returns the Discogs original-release label; v2 returns the DJ-typed (or sub-label) string the librarian filed in tubafrenzy. Examples:

| track | v1.label (Discogs) | v2.label (tubafrenzy/inline) |
|---|---|---|
| Los Enanitos Verdes — Lamento Boliviano | EMI | EMI Latin |
| Altin Gun — Halkali Seker | Les Disques Bongo Joe | ATO |
| Ana Frango Eletrico — A Sua Diversao | Mr Bongo | Psychic Hotline |
| Jimmy McGriff — The Bird Wave | Blue Note | Stereo |
| Meltycanon — Veldt | Not On Label | s/r |
| Wilco — Heavy Metal Drummer | Nonesuch | Nonesuch Records |

Which is "right" is a product call. v2 preserves the librarian's filing; v1 substitutes the canonical label from Discogs.

#### Search-URL drift (bandcamp / soundcloud / youtube — 18–20 rows each)

All three platforms produce search URLs (`bandcamp.com/search?q=…`) when no deep link is available. The two sides plug *different search terms* into the query. Pattern: **v1 follows a downstream LML artist resolution that sometimes resolves to the wrong artist** and emits a search URL for that artist's catalog instead of the actual playcut.

Examples:

- *Olivia Neutron-John — March*  
  v1: `?q=Anna%20Nasty%20March` (wrong artist)  
  v2: `?q=Olivia%20Neutron-John%20March` (correct)
- *Maria BC — Safety*  
  v1: `?q=Santana%20Safety` (wrong artist)  
  v2: `?q=Maria%20BC%20Safety` (correct)
- *Cass McCombs — I Never Dream About Trains*  
  v1: `?q=Cass%20McCombs%20I%20Never%20Dream%20About%20Trains` (correct)  
  v2: `?q=Cass%20McCombs%20Interior%20Live%20Oak` (different — and wrong — track)

Same root cause as the *Salimata — Cake Up* → The Ex spurious resolution we found earlier. v1 and v2 differ here because they were resolved at different times against different upstream states.

#### Apple Music (3 rows)

v1 and v2 resolved to *different* Apple Music albums for the same playcut (different release IDs). Both URLs are real; they just point at different masters/compilations.

#### Artwork (1 row), Artist bio (1 row)

- *Salimata — Cake Up*: v1 has the `q:90/h:600/w:599` Discogs image; v2 has the `q:40/h:150/w:150` thumbnail variant. Both URLs encode the same source S3 key.
- *Los Enanitos Verdes*: v1 bio is 714 chars; v2 bio is 373 chars. Different snapshots of the same Discogs artist record.

### 3. Three independent failure modes, summarized

1. **v2 inline enrichment has gaps.** BS's pipeline failed (or never ran) on a sizable minority of rows, leaving fields permanently nil. Visible to users as missing Spotify/Apple/Discogs/artwork buttons even though the v1 path can produce them.
2. **`label` drifts everywhere.** v2 carries the DJ-typed label; v1 substitutes the Discogs canonical. The choice has product implications for how station identity is reflected vs. how external catalogs categorize releases.
3. **v1's downstream resolver follows wrong-artist matches** for some playcuts, generating search URLs (and the occasional Apple Music URL) for unrelated artists. v2's frozen values are sometimes more correct on this axis — same root cause as the cross-cache identity issues already tracked elsewhere.

### Endpoint behavior notes

- `tubafrenzy /playlists/recentEntries?v=2&n=N` honors `n` up to ~150 (returned 112 actual playcuts at `n=150`).
- `api.wxyc.org/flowsheet` defaults to ~22 entries; `?limit=N` honors larger values (also returned 112 playcuts at `?limit=150` after filtering non-track entries).
- Without explicit pagination, comparing only the live window severely under-counts divergence — the current show is freshly enriched on both sides, so most fields agree. Older playcuts are where the gaps and drift live.

## Caveats

- This tool exercises the **iOS v1 metadata path** specifically — `PlaycutMetadataService` against the proxy endpoints. If the same `(artist, song)` is later re-enriched by BS, v2's value may change; this report is a point-in-time snapshot.
- Search-URL terms come from the proxy, which uses an internal artist-resolution that can follow wrong-artist matches. That's an upstream bug surfaced in v1, not a behavior of this tool.
- The tool does not interact with the iOS disk cache (`CacheCoordinator.Metadata`). v1 values reflect *current* proxy state, not whatever the device may have cached from a prior run.
