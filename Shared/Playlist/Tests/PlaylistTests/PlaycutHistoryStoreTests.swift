//
//  PlaycutHistoryStoreTests.swift
//  Playlist
//
//  Tests for PlaycutHistoryStore covering day-bucketed persistence keyed on broadcast
//  date, newest-snapshot-wins dedup within and across buckets, ingest serialization and
//  read-failure safety, the durable rotation set with refreshed lifespan and per-row age
//  pruning, TTL anchoring to broadcast day via an injected Clock, and the PlaylistService
//  subscription loop.
//
//  Created by Jake Bromberg on 07/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import CachingTesting
import PlaylistTesting
@testable import Playlist
@testable import Caching

// MARK: - Fixture timestamps

/// The test clock's "now": 2026-07-02T00:00:00Z, in the reference-date domain used by `Clock`.
private let testNow: TimeInterval = Date(timeIntervalSince1970: 1_782_950_400).timeIntervalSinceReferenceDate

/// 2026-07-01T15:00:00Z — 11:00 AM ET on July 1, nine hours before `testNow`. Milliseconds since epoch.
private let july1MorningET: UInt64 = 1_782_918_000_000

/// 2026-07-02T03:30:00Z — 11:30 PM ET on July 1 (station day rolls at ET midnight).
private let july1LateNightET: UInt64 = 1_782_963_000_000

/// 2026-06-28T15:00:00Z — 11:00 AM ET on June 28.
private let june28MorningET: UInt64 = 1_782_658_800_000

/// 2026-03-01T15:00:00Z — ~122 days before `testNow`, outside the 90-day history window.
private let march1MorningET: UInt64 = 1_772_377_200_000

private let day: TimeInterval = 24 * 60 * 60
private let ninetyDays: TimeInterval = 90 * day
private let ninetyOneDays: TimeInterval = 91 * day

/// A broadcast hour a whole number of days after `july1MorningET`, in milliseconds since epoch.
private func hoursMS(daysAfterJuly1 days: UInt64) -> UInt64 {
    july1MorningET + days * 86_400_000
}

// MARK: - Tests

@Suite("PlaycutHistoryStore Tests")
struct PlaycutHistoryStoreTests {

    // MARK: - Day bucketing

    @Test("Day key derives from broadcast date in station time zone")
    func dayKeyUsesStationBroadcastDate() {
        // 11AM ET and 11:30PM ET on July 1 share a station day, even though the
        // late-night play falls on July 2 in UTC.
        #expect(PlaycutHistoryStore.dayKey(for: .stub(hour: july1MorningET)) == "day.2026-07-01")
        #expect(PlaycutHistoryStore.dayKey(for: .stub(hour: july1LateNightET)) == "day.2026-07-01")
        #expect(PlaycutHistoryStore.dayKey(for: .stub(hour: june28MorningET)) == "day.2026-06-28")
    }

    @Test("Ingest writes one bucket per broadcast day")
    func ingestBucketsByBroadcastDay() async throws {
        let (store, coordinator, _) = makeStore()

        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: "DOGA"),
            .stub(id: 2, hour: july1LateNightET, songTitle: "Aluminum Tunes", artistName: "Stereolab", releaseTitle: "Aluminum Tunes"),
            .stub(id: 3, hour: june28MorningET, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix"),
        ])

        let dayKeys = await coordinator.allEntries()
            .map(\.key)
            .filter { $0.hasPrefix("day.") }
            .sorted()
        #expect(dayKeys == ["day.2026-06-28", "day.2026-07-01"])

        let july1: [Playcut] = try await coordinator.value(for: "day.2026-07-01")
        #expect(Set(july1.map(\.id)) == [1, 2])
    }

    @Test("Day bucket lifespan is anchored to the broadcast day, not the write time")
    func dayBucketLifespanAnchorsToBroadcastDay() async throws {
        let (store, coordinator, _) = makeStore()

        await store.ingest([.stub(id: 1, hour: july1MorningET)])

        // The playcut was broadcast nine hours before the clock's "now", so the
        // remaining lifespan is 90 days minus those nine hours: the bucket expires
        // 90 days after broadcast regardless of when it was written.
        let entry = try #require(await coordinator.allEntries().first { $0.key == "day.2026-07-01" })
        #expect(entry.metadata.lifespan == ninetyDays - 9 * 60 * 60)
    }

    @Test("Re-ingesting a bucket does not extend its life beyond broadcast + 90 days")
    func rewriteDoesNotExtendBucketLife() async {
        let (store, _, clock) = makeStore()

        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "Back, Baby", artistName: "Jessica Pratt", releaseTitle: "On Your Own Love Again"),
        ])

        // 89 days later an enrichment re-broadcast rewrites the bucket…
        clock.advance(by: 89 * day)
        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "Back, Baby", labelName: "Drag City", artistName: "Jessica Pratt", releaseTitle: "On Your Own Love Again"),
        ])

        // …but the bucket still expires 90 days after broadcast, not 90 days
        // after the rewrite.
        clock.advance(by: 2 * day)
        let all = await store.allIndexable()
        #expect(all.isEmpty)
    }

    @Test("Playcuts broadcast outside the 90-day window are rejected at ingest")
    func staleRowsDoNotResurrectExpiredBuckets() async {
        let (store, coordinator, _) = makeStore()

        // A stale re-broadcast carrying rows from ~122 days ago: the non-rotation
        // row must not resurrect a day bucket the TTL machinery already pruned.
        await store.ingest([
            .stub(id: 1, hour: march1MorningET, songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: "DOGA"),
            .stub(id: 2, hour: march1MorningET, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: true),
        ])

        let dayKeys = await coordinator.allEntries().map(\.key).filter { $0.hasPrefix("day.") }
        #expect(dayKeys.isEmpty)

        // The rotation row is still younger than the rotation window, so it
        // remains reachable through the rotation set.
        let all = await store.allIndexable()
        #expect(all.map(\.id) == [2])
    }

    // MARK: - Dedup

    @Test("Re-ingesting the same id keeps one row with the newest snapshot")
    func newestSnapshotWinsWithinBucket() async {
        let (store, _, _) = makeStore()

        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "Back, Baby", artistName: "Jessica Pratt", releaseTitle: "On Your Own Love Again"),
        ])

        // Enrichment re-broadcast: same id, metadata filled in.
        let enriched = Playcut.stub(
            id: 1,
            hour: july1MorningET,
            songTitle: "Back, Baby",
            labelName: "Drag City",
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again",
            artworkURL: URL(string: "https://example.org/oyola.jpg")
        )
        await store.ingest([enriched])

        let all = await store.allIndexable()
        #expect(all.count == 1)
        #expect(all.first?.labelName == "Drag City")
        #expect(all.first?.artworkURL != nil)
    }

    @Test("When the same id lands in two buckets, the fresher snapshot wins regardless of bucket order")
    func fresherSnapshotWinsAcrossBuckets() async {
        // tubafrenzy mutates a playcut's hour in place when entries move across an
        // hourly breakpoint, so the same id can land in two adjacent day buckets.
        // Case 1: the fresher snapshot sits in the OLDER bucket.
        let (store, _, _) = makeStore()
        await store.ingest([
            .stub(id: 1, hour: july1MorningET, timeCreated: 1_782_918_000_000, songTitle: "stale snapshot", artistName: "Stereolab"),
        ])
        await store.ingest([
            .stub(id: 1, hour: june28MorningET, timeCreated: 1_782_918_500_000, songTitle: "fresh snapshot", artistName: "Stereolab"),
        ])

        let all = await store.allIndexable()
        #expect(all.count == 1)
        #expect(all.first?.songTitle == "fresh snapshot")

        let byID = await store.playcuts(ids: [1])
        #expect(byID.first?.songTitle == "fresh snapshot")

        // Case 2: the fresher snapshot sits in the NEWER bucket.
        let (store2, _, _) = makeStore()
        await store2.ingest([
            .stub(id: 1, hour: june28MorningET, timeCreated: 1_782_918_000_000, songTitle: "stale snapshot", artistName: "Stereolab"),
        ])
        await store2.ingest([
            .stub(id: 1, hour: july1MorningET, timeCreated: 1_782_918_500_000, songTitle: "fresh snapshot", artistName: "Stereolab"),
        ])

        let all2 = await store2.allIndexable()
        #expect(all2.count == 1)
        #expect(all2.first?.songTitle == "fresh snapshot")
    }

    @Test("A play moved across midnight evicts its stale copy from the adjacent bucket")
    func hourMoveAcrossMidnightEvictsStaleAdjacentCopy() async {
        let (store, coordinator, _) = makeStore()

        // 00:30 ET on July 2 — the play lands in the 2026-07-02 bucket.
        let july2EarlyET: UInt64 = 1_782_966_600_000
        await store.ingest([
            .stub(id: 1, hour: july2EarlyET, timeCreated: july2EarlyET, songTitle: "stale snapshot", artistName: "Stereolab"),
        ])

        // Deleting a breakpoint moves radioHour back one hour — across midnight
        // into the 2026-07-01 bucket — WITHOUT touching timeCreated (tubafrenzy's
        // UPDATE_SQL never does), so the two snapshots tie exactly and no
        // read-side recency heuristic can pick the right one.
        await store.ingest([
            .stub(id: 1, hour: july1LateNightET, timeCreated: july2EarlyET, songTitle: "corrected snapshot", artistName: "Stereolab"),
        ])

        let all = await store.allIndexable()
        #expect(all.count == 1)
        #expect(all.first?.songTitle == "corrected snapshot")

        // The stale copy is evicted from the adjacent bucket at ingest, not merely
        // shadowed at read — and the emptied bucket entry is removed outright.
        let dayKeys = await coordinator.allEntries().map(\.key).filter { $0.hasPrefix("day.") }
        #expect(dayKeys == ["day.2026-07-01"])
    }

    @Test("A stale out-of-order batch does not evict a newer adjacent snapshot")
    func staleBatchDoesNotEvictNewerAdjacentSnapshot() async {
        let (store, _, _) = makeStore()
        let july2EarlyET: UInt64 = 1_782_966_600_000

        // The corrected (post-move, newer timeCreated) snapshot lands first.
        await store.ingest([
            .stub(id: 1, hour: july1LateNightET, timeCreated: 1_782_966_900_000, songTitle: "corrected snapshot", artistName: "Stereolab"),
        ])

        // A stale batch replays the pre-move snapshot out of order. Its adjacent-
        // bucket eviction must spare the strictly newer stored copy — the read
        // backstop can rank these (timeCreated differs), but only if it survives.
        await store.ingest([
            .stub(id: 1, hour: july2EarlyET, timeCreated: 1_782_966_600_000, songTitle: "stale snapshot", artistName: "Stereolab"),
        ])

        let all = await store.allIndexable()
        #expect(all.count == 1)
        #expect(all.first?.songTitle == "corrected snapshot")
    }

    @Test("A stale same-bucket replay does not overwrite a newer stored snapshot")
    func staleReplayDoesNotOverwriteNewerSameBucketSnapshot() async {
        let (store, _, _) = makeStore()

        // BG refresh directly ingested the corrected snapshot…
        await store.ingest([
            .stub(id: 1, hour: july1MorningET, timeCreated: 1_782_918_500_000, songTitle: "corrected snapshot", artistName: "Stereolab"),
        ])

        // …then the subscription replays the older cached playlist into the SAME
        // bucket. The merge must spare the strictly newer stored row.
        await store.ingest([
            .stub(id: 1, hour: july1MorningET, timeCreated: 1_782_918_000_000, songTitle: "stale snapshot", artistName: "Stereolab"),
        ])

        let all = await store.allIndexable()
        #expect(all.count == 1)
        #expect(all.first?.songTitle == "corrected snapshot")
    }

    @Test("Rotation eligibility survives same-batch dedup by a non-rotation correction")
    func rotationEligibilityComesFromPreDedupBatch() async {
        let (store, _, clock) = makeStore()

        // One batch carries the same id twice: an older rotation==true snapshot
        // collapsed by a newer rotation==false correction. Eligibility must come
        // from the pre-dedup batch — split across two batches these snapshots
        // would induct then stickily refresh, and one batch must behave the same.
        await store.ingest([
            .stub(id: 1, hour: july1MorningET, timeCreated: 1_782_918_000_000, songTitle: "Moon Pxi", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: true),
            .stub(id: 1, hour: july1MorningET, timeCreated: 1_782_918_500_000, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: false),
        ])

        // Once the day bucket expires, only the rotation set can serve the id —
        // with the corrected title from the surviving snapshot.
        clock.advance(by: ninetyOneDays)
        let all = await store.allIndexable()
        #expect(all.map(\.id) == [1])
        #expect(all.first?.songTitle == "Moon Pix")
    }

    @Test("Same-batch duplicates keep only the freshest snapshot")
    func sameBatchDuplicatesKeepFreshest() async {
        let (store, coordinator, _) = makeStore()
        let july2EarlyET: UInt64 = 1_782_966_600_000

        // One concatenated batch carries the same id in two adjacent-day buckets;
        // without entry dedup, Dictionary iteration order decides which bucket's
        // eviction pass wins.
        await store.ingest([
            .stub(id: 1, hour: july2EarlyET, timeCreated: 1_782_966_600_000, songTitle: "stale snapshot", artistName: "Stereolab"),
            .stub(id: 1, hour: july1LateNightET, timeCreated: 1_782_966_900_000, songTitle: "corrected snapshot", artistName: "Stereolab"),
        ])

        let all = await store.allIndexable()
        #expect(all.count == 1)
        #expect(all.first?.songTitle == "corrected snapshot")

        let dayKeys = await coordinator.allEntries().map(\.key).filter { $0.hasPrefix("day.") }
        #expect(dayKeys == ["day.2026-07-01"])
    }

    // MARK: - Ingest safety

    @Test("A failed read of an intact entry skips the write instead of truncating it")
    func ingestSkipsWriteWhenReadFails() async {
        let cache = FailingReadCache()
        let clock = MockClock(now: testNow)
        let coordinator = CacheCoordinator(cache: cache, clock: clock)
        let store = PlaycutHistoryStore(cacheCoordinator: coordinator, clock: clock)

        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: "DOGA"),
            .stub(id: 2, hour: july1MorningET, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: true),
        ])

        // Reads now fail while the entries remain intact on disk. Writing a merge
        // of "nothing" over them would truncate the history and rotation set.
        cache.failReads = true
        await store.ingest([
            .stub(id: 3, hour: july1MorningET, songTitle: "Aluminum Tunes", artistName: "Stereolab", releaseTitle: "Aluminum Tunes", rotation: true),
        ])
        cache.failReads = false

        let all = await store.allIndexable()
        #expect(Set(all.map(\.id)) == [1, 2])
    }

    @Test("Overlapping ingests are serialized so neither update is lost", .timeLimit(.minutes(1)))
    func overlappingIngestsBothPersist() async {
        let cache = SlowFirstReadCache()
        let clock = MockClock(now: testNow)
        let coordinator = CacheCoordinator(cache: cache, clock: clock)
        let store = PlaycutHistoryStore(cacheCoordinator: coordinator, clock: clock)

        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: "DOGA"),
        ])

        // The next read stalls, holding a stale snapshot of the bucket while a
        // second ingest lands — mirroring the subscription loop racing the
        // BackgroundRefreshController's direct ingest call.
        cache.armSlowRead()
        async let first: Void = store.ingest([
            .stub(id: 2, hour: july1MorningET, songTitle: "Aluminum Tunes", artistName: "Stereolab", releaseTitle: "Aluminum Tunes"),
        ])
        try? await Task.sleep(for: .milliseconds(50))
        async let second: Void = store.ingest([
            .stub(id: 3, hour: july1MorningET, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix"),
        ])
        _ = await (first, second)

        let all = await store.allIndexable()
        #expect(Set(all.map(\.id)) == [1, 2, 3])
    }

    @Test("Re-ingesting an unchanged batch performs no rewrite")
    func unchangedBatchDoesNotRewrite() async throws {
        let (store, coordinator, clock) = makeStore()
        let batch: [Playcut] = [
            .stub(id: 1, hour: july1MorningET, songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: "DOGA"),
            .stub(id: 2, hour: july1MorningET, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: true),
        ]

        await store.ingest(batch)
        let timestampsBefore = Dictionary(
            uniqueKeysWithValues: await coordinator.allEntries().map { ($0.key, $0.metadata.timestamp) }
        )

        // BGAppRefresh can replay the same window multiple times per wake; an
        // unchanged batch must not rewrite (and re-timestamp) every entry.
        clock.advance(by: 60 * 60)
        await store.ingest(batch)

        let timestampsAfter = Dictionary(
            uniqueKeysWithValues: await coordinator.allEntries().map { ($0.key, $0.metadata.timestamp) }
        )
        #expect(timestampsAfter == timestampsBefore)
    }

    // MARK: - Reads

    @Test("playcuts(ids:) returns matches across buckets and omits unknown ids")
    func playcutsByIDSpansBucketsAndOmitsMisses() async {
        let (store, _, _) = makeStore()

        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: "DOGA"),
            .stub(id: 2, hour: june28MorningET, songTitle: "Call Your Name", artistName: "Chuquimamani-Condori", releaseTitle: "Edits"),
            .stub(id: 3, hour: june28MorningET, songTitle: "In a Sentimental Mood", artistName: "Duke Ellington & John Coltrane", releaseTitle: "Duke Ellington & John Coltrane", rotation: true),
        ])

        let found = await store.playcuts(ids: [1, 2, 3, 999])
        #expect(Set(found.map(\.id)) == [1, 2, 3])
    }

    @Test("allIndexable returns the union of day buckets and rotation set, deduped")
    func allIndexableUnionsBucketsAndRotation() async {
        let (store, _, _) = makeStore()

        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: "DOGA"),
            .stub(id: 2, hour: june28MorningET, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: true),
        ])

        let all = await store.allIndexable()
        // Playcut 2 lives in both its day bucket and the rotation set — it must appear once.
        #expect(Set(all.map(\.id)) == [1, 2])
        #expect(all.count == 2)
    }

    // MARK: - TTL pruning

    @Test("Non-rotation playcuts are pruned once their day bucket expires")
    func expiredDayBucketsArePruned() async {
        let (store, _, clock) = makeStore()

        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "Aluminum Tunes", artistName: "Stereolab", releaseTitle: "Aluminum Tunes"),
        ])

        clock.advance(by: ninetyOneDays)

        let all = await store.allIndexable()
        #expect(all.isEmpty)
        let found = await store.playcuts(ids: [1])
        #expect(found.isEmpty)
    }

    // MARK: - Rotation set

    @Test("Rotation set is written with a 365-day lifespan")
    func rotationLifespanIs365Days() async throws {
        let (store, coordinator, _) = makeStore()

        await store.ingest([.stub(id: 1, hour: july1MorningET, rotation: true)])

        let entry = try #require(await coordinator.allEntries().first { $0.key == "rotation-set" })
        #expect(entry.metadata.lifespan == 365 * day)
    }

    @Test("Rotation playcut outlives its expired day bucket in both reads")
    func rotationSurvivesDayBucketExpiry() async {
        let (store, _, clock) = makeStore()

        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: true),
            .stub(id: 2, hour: july1MorningET, songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: "DOGA"),
        ])

        clock.advance(by: ninetyOneDays)

        let all = await store.allIndexable()
        #expect(all.map(\.id) == [1])
        let found = await store.playcuts(ids: [1, 2])
        #expect(found.map(\.id) == [1])
    }

    @Test("Rotation set survives relaunch with a fresh coordinator over the same cache")
    func rotationSurvivesRelaunch() async {
        let cache = InMemoryCache()
        let clock = MockClock(now: testNow)
        let firstCoordinator = CacheCoordinator(cache: cache, clock: clock)
        let firstStore = PlaycutHistoryStore(cacheCoordinator: firstCoordinator, clock: clock)

        await firstStore.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: true),
        ])

        // Relaunch six months later: the init purge must delete the aged day
        // bucket but spare the rotation set, whose finite 365-day lifespan is
        // what keeps it from being swept as a legacy infinite-lifespan entry.
        clock.advance(by: 180 * day)
        let secondCoordinator = CacheCoordinator(cache: cache, clock: clock)
        await secondCoordinator.waitForPurge()
        let secondStore = PlaycutHistoryStore(cacheCoordinator: secondCoordinator, clock: clock)

        let all = await secondStore.allIndexable()
        #expect(all.map(\.id) == [1])
    }

    @Test("Rotation lifespan is refreshed on every write")
    func rotationLifespanRefreshesOnWrite() async {
        let (store, _, clock) = makeStore()

        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: true),
        ])

        // 300 days later a new rotation play rewrites the set, refreshing its lifespan.
        clock.advance(by: 300 * day)
        await store.ingest([
            .stub(id: 2, hour: hoursMS(daysAfterJuly1: 300), songTitle: "In a Sentimental Mood", artistName: "Duke Ellington & John Coltrane", releaseTitle: "Duke Ellington & John Coltrane", rotation: true),
        ])

        // 400 days after the first write — past the original 365-day entry
        // lifespan, but only 100 days past the refresh — the entry must still be
        // alive. The first row's broadcast is now over a year old, so the
        // read-side age filter retires it; the refreshed entry serves the second.
        clock.advance(by: 100 * day)
        let all = await store.allIndexable()
        #expect(all.map(\.id) == [2])
    }

    @Test("Rotation rows broadcast more than a year ago are pruned at write time")
    func rotationRowsOlderThanAYearArePrunedOnWrite() async {
        let (store, _, clock) = makeStore()

        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: true),
        ])

        // Keep the set entry alive with a mid-way write, then write again once the
        // first row's broadcast is over a year old: the write must drop it, so the
        // set is bounded by age rather than accreting every rotation play forever.
        clock.advance(by: 200 * day)
        await store.ingest([
            .stub(id: 2, hour: hoursMS(daysAfterJuly1: 200), songTitle: "In a Sentimental Mood", artistName: "Duke Ellington & John Coltrane", releaseTitle: "Duke Ellington & John Coltrane", rotation: true),
        ])

        clock.advance(by: 200 * day)
        await store.ingest([
            .stub(id: 3, hour: hoursMS(daysAfterJuly1: 400), songTitle: "Call Your Name", artistName: "Chuquimamani-Condori", releaseTitle: "Edits", rotation: true),
        ])

        let all = await store.allIndexable()
        #expect(Set(all.map(\.id)) == [2, 3])
    }

    @Test("Rotation rows broadcast over a year ago are excluded at read time")
    func rotationReadFiltersRowsOlderThanAYear() async {
        let (store, coordinator, _) = makeStore()

        // Seed the rotation set directly with a freshly WRITTEN entry containing
        // one row broadcast ~370 days ago: without further ingests, the write-time
        // prune never runs again, so only a read-side filter can retire the row.
        let ancientHour: UInt64 = july1MorningET - 370 * 86_400_000
        await coordinator.set(
            value: [
                Playcut.stub(id: 1, hour: ancientHour, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: true),
                Playcut.stub(id: 2, hour: july1MorningET, songTitle: "In a Sentimental Mood", artistName: "Duke Ellington & John Coltrane", releaseTitle: "Duke Ellington & John Coltrane", rotation: true),
            ],
            for: "rotation-set",
            lifespan: 365 * day
        )

        let all = await store.allIndexable()
        #expect(all.map(\.id) == [2])
        let found = await store.playcuts(ids: [1, 2])
        #expect(found.map(\.id) == [2])
    }

    @Test("Far-future rows are rejected everywhere; near-future rows clamp to the full lifespan")
    func futureDatedRowsAreRejectedOrClamped() async throws {
        let (store, coordinator, _) = makeStore()

        // A row claiming broadcast 30 days from now (corrupt feed or clock skew
        // beyond tolerance) must not be persisted in any form.
        let farFuture: UInt64 = 1_785_542_400_000
        await store.ingest([
            .stub(id: 1, hour: farFuture, songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: "DOGA", rotation: true),
        ])

        #expect(await coordinator.allEntries().isEmpty)
        #expect(await store.allIndexable().isEmpty)

        // Modest clock skew (an hour ahead) is tolerated, but the bucket lifespan
        // clamps to the window size instead of exceeding it.
        let nearFuture: UInt64 = 1_782_954_000_000
        await store.ingest([
            .stub(id: 2, hour: nearFuture, songTitle: "Aluminum Tunes", artistName: "Stereolab", releaseTitle: "Aluminum Tunes"),
        ])

        let entry = try #require(await coordinator.allEntries().first { $0.key.hasPrefix("day.") })
        #expect(entry.metadata.lifespan == ninetyDays)
        let all = await store.allIndexable()
        #expect(all.map(\.id) == [2])
    }

    @Test("A non-rotation re-broadcast of a rotation track refreshes its rotation-set row")
    func nonRotationSnapshotRefreshesRotationRow() async {
        let (store, _, clock) = makeStore()

        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "Moon Pxi", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: true),
        ])

        // A later snapshot corrects the title but arrives with rotation == false;
        // membership is sticky, so the stored rotation row must still refresh.
        await store.ingest([
            .stub(id: 1, hour: july1MorningET, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: false),
        ])

        // Once the day bucket expires, the surviving rotation copy carries the fix.
        clock.advance(by: ninetyOneDays)
        let all = await store.allIndexable()
        #expect(all.map(\.id) == [1])
        #expect(all.first?.songTitle == "Moon Pix")
    }

    // MARK: - Subscription

    @Test("start(observing:) ingests playlists from an injected stream", .timeLimit(.minutes(1)))
    func startObservingIngestsFromStream() async throws {
        let (store, _, _) = makeStore()
        let (stream, continuation) = AsyncStream.makeStream(of: Playlist.self)

        await store.start(observing: stream)
        continuation.yield(.stub(playcuts: [
            .stub(id: 1, hour: july1MorningET, songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: "DOGA"),
        ]))
        continuation.finish()

        try await waitUntil { await store.allIndexable().count == 1 }
        let all = await store.allIndexable()
        #expect(all.count == 1)
        #expect(all.first?.artistName == "Juana Molina")
    }

    @Test("start(observing:) ingests playlists from a live PlaylistService", .timeLimit(.minutes(1)))
    func startObservingIngestsFromPlaylistService() async throws {
        let (store, _, _) = makeStore()
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 1, hour: july1MorningET, songTitle: "Aluminum Tunes", artistName: "Stereolab", releaseTitle: "Aluminum Tunes"),
        ])
        let service = PlaylistService(
            fetcher: fetcher,
            interval: 60,
            cacheCoordinator: CacheCoordinator(cache: InMemoryCache())
        )

        await store.start(observing: service)

        try await waitUntil { await store.allIndexable().count == 1 }
        let all = await store.allIndexable()
        #expect(all.count == 1)
        #expect(all.first?.artistName == "Stereolab")
    }

    // MARK: - Stored-format compatibility

    @Test("Frozen day-bucket JSON from the current schema stays decodable")
    func frozenDayBucketFixtureDecodes() throws {
        // Golden fixture: a day bucket as PlaycutHistoryStore writes it today.
        // History entries live on disk for up to a year, so Playcut decoding must
        // stay tolerant of rows written by OLDER app versions — if a future field
        // is added with a bare `container.decode`, this test turns the resulting
        // silent history loss into a red build.
        let frozenBucket = """
        [
          {
            "id": 1,
            "hour": 1782918000000,
            "chronOrderID": 1,
            "timeCreated": 1782918000000,
            "songTitle": "la paradoja",
            "labelName": "Sonamos",
            "artistName": "Juana Molina",
            "releaseTitle": "DOGA",
            "rotation": false
          },
          {
            "id": 2,
            "hour": 1782918300000,
            "chronOrderID": 2,
            "songTitle": "In a Sentimental Mood",
            "artistName": "Duke Ellington & John Coltrane"
          },
          {
            "id": 3,
            "hour": 1782918600000,
            "chronOrderID": 3,
            "timeCreated": 1782918600000,
            "songTitle": "Moon Pix",
            "artistName": "Cat Power",
            "releaseTitle": "Moon Pix",
            "labelName": "Matador Records",
            "rotation": true,
            "artworkURL": "https://example.org/moon-pix.jpg",
            "discogsURL": "https://www.discogs.com/release/370846",
            "releaseYear": 1998,
            "spotifyURL": "https://open.spotify.com/track/0Nz5P2WBhBSXNjKihrVSbJ",
            "artistBio": "Chan Marshall, known as Cat Power.",
            "genres": ["Rock"],
            "styles": ["Indie Rock"]
          }
        ]
        """

        let bucket = try JSONDecoder().decode([Playcut].self, from: Data(frozenBucket.utf8))

        #expect(bucket.count == 3)
        #expect(bucket[0].labelName == "Sonamos")
        // Minimal row: optional fields absent, timeCreated falls back to hour.
        #expect(bucket[1].timeCreated == bucket[1].hour)
        #expect(bucket[1].rotation == false)
        #expect(bucket[2].rotation == true)
        #expect(bucket[2].artworkURL != nil)
        #expect(bucket[2].releaseYear == 1998)
    }

    // MARK: - DiskCache integration

    @Test("Day-bucketed history round-trips through a real DiskCache")
    func historyRoundTripsThroughDiskCache() async throws {
        let subdirectory = "playcut-history-test-\(UUID().uuidString)"
        defer {
            if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                try? FileManager.default.removeItem(at: caches.appending(path: subdirectory))
            }
        }

        // Real clock + real files: broadcast hours must fall inside the live
        // 90-day window for the anchored lifespans to accept them.
        let recentHour = UInt64(Date.now.addingTimeInterval(-2 * 60 * 60).timeIntervalSince1970 * 1000)
        let coordinator = CacheCoordinator(cache: DiskCache(subdirectory: subdirectory))
        let store = PlaycutHistoryStore(cacheCoordinator: coordinator)

        await store.ingest([
            .stub(id: 1, hour: recentHour, songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: "DOGA"),
            .stub(id: 2, hour: recentHour, songTitle: "Moon Pix", artistName: "Cat Power", releaseTitle: "Moon Pix", rotation: true),
        ])

        // A second coordinator + store over the same directory simulates relaunch:
        // "day."-prefixed key enumeration must round-trip through real filenames.
        let relaunchedCoordinator = CacheCoordinator(cache: DiskCache(subdirectory: subdirectory))
        await relaunchedCoordinator.waitForPurge()
        let relaunchedStore = PlaycutHistoryStore(cacheCoordinator: relaunchedCoordinator)

        let all = await relaunchedStore.allIndexable()
        #expect(Set(all.map(\.id)) == [1, 2])
        let found = await relaunchedStore.playcuts(ids: [2])
        #expect(found.map(\.id) == [2])
    }

    // MARK: - Helpers

    private func makeStore() -> (PlaycutHistoryStore, CacheCoordinator, MockClock) {
        let clock = MockClock(now: testNow)
        let coordinator = CacheCoordinator(cache: InMemoryCache(), clock: clock)
        let store = PlaycutHistoryStore(cacheCoordinator: coordinator, clock: clock)
        return (store, coordinator, clock)
    }

    /// Polls `condition` for up to ~5 seconds, returning when it holds.
    ///
    /// Callers re-assert the condition with `#expect` afterwards so a timeout
    /// fails with diagnostics rather than a bare suite time limit.
    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<250 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

// MARK: - Test Doubles

/// Wraps `InMemoryCache` but can simulate transient read failures: `data(for:)`
/// returns nil while metadata stays intact — the shape `DiskCache` produces when
/// the backing file exists but cannot be read.
private final class FailingReadCache: Cache, @unchecked Sendable {
    private let inner = InMemoryCache()
    private let lock = NSLock()
    private var _failReads = false

    var failReads: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _failReads
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _failReads = newValue
        }
    }

    func metadata(for key: String) -> CacheMetadata? {
        inner.metadata(for: key)
    }

    func data(for key: String) -> Data? {
        failReads ? nil : inner.data(for: key)
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        inner.set(data, metadata: metadata, for: key)
    }

    func remove(for key: String) {
        inner.remove(for: key)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        inner.allMetadata()
    }

    func clearAll() {
        inner.clearAll()
    }

    func totalSize() -> Int64 {
        inner.totalSize()
    }
}

/// Wraps `InMemoryCache` but stalls the first `data(for:)` read after `armSlowRead()`,
/// widening the read-merge-write window so overlapping ingests deterministically
/// interleave unless the store serializes them.
private final class SlowFirstReadCache: Cache, @unchecked Sendable {
    private let inner = InMemoryCache()
    private let lock = NSLock()
    private var slowReadArmed = false

    func armSlowRead() {
        lock.lock()
        defer { lock.unlock() }
        slowReadArmed = true
    }

    private func consumeSlowRead() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard slowReadArmed else { return false }
        slowReadArmed = false
        return true
    }

    func metadata(for key: String) -> CacheMetadata? {
        inner.metadata(for: key)
    }

    func data(for key: String) -> Data? {
        if consumeSlowRead() {
            Thread.sleep(forTimeInterval: 0.15)
        }
        return inner.data(for: key)
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        inner.set(data, metadata: metadata, for: key)
    }

    func remove(for key: String) {
        inner.remove(for: key)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        inner.allMetadata()
    }

    func clearAll() {
        inner.clearAll()
    }

    func totalSize() -> Int64 {
        inner.totalSize()
    }
}
