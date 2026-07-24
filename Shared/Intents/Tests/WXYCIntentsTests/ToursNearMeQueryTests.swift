//
//  ToursNearMeQueryTests.swift
//  WXYCIntents
//
//  TDD coverage for OT-C2 (WXYC/wxyc-ios-64#625): the date-window narrowing,
//  the on-device loved-tier preference (and its cold-start fallback), the
//  result cap, and -- the load-bearing privacy assertion -- that the curated
//  window fetch never varies with `likedArtists`.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import ConcertsTesting
import Foundation
import Testing
@testable import WXYCIntents

/// Builds a station-zone (`America/New_York`) instant at the given hour on the
/// given calendar day, mirroring `ConcertFilterStateTests`' helper so "today"
/// is unambiguous regardless of the host machine's zone.
private func stationDay(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
}

@Suite("TouringDateWindow")
struct TouringDateWindowTests {
    @Test(
        "bridges to the matching ConcertFilterState.DateWindow",
        arguments: [
            (TouringDateWindow.tonight, ConcertFilterState.DateWindow.tonight),
            (TouringDateWindow.thisWeekend, ConcertFilterState.DateWindow.thisWeekend),
            (TouringDateWindow.next7Days, ConcertFilterState.DateWindow.next7Days),
        ]
    )
    func filterWindowBridges(siriWindow: TouringDateWindow, domainWindow: ConcertFilterState.DateWindow) {
        #expect(siriWindow.filterWindow == domainWindow)
    }
}

@Suite("ToursNearMeQuery.matchingConcerts")
struct ToursNearMeQueryMatchingConcertsTests {
    // 2026-08-01 is a Saturday; the coming Sunday is 2026-08-02.
    private static let saturdayNow = stationDay(2026, 8, 1)

    @Test("narrows to the date window before considering likes")
    func narrowsToDateWindow() {
        let tonight = Concert.stub(id: 1, startsOn: stationDay(2026, 8, 1, hour: 0), headliningArtistId: nil)
        let nextWeek = Concert.stub(id: 2, startsOn: stationDay(2026, 8, 6, hour: 0), headliningArtistId: nil)

        let matches = ToursNearMeQuery.matchingConcerts(
            concerts: [tonight, nextWeek],
            dateWindow: .tonight,
            likedArtists: [],
            now: Self.saturdayNow
        )

        #expect(matches.map(\.id) == [tonight.id])
    }

    @Test("with no likes, falls back to the plain date-filtered window")
    func fallsBackToDateFilteredWhenNoLikes() {
        let juana = Concert.stub(id: 1, startsOn: Self.saturdayNow, headliningArtistRaw: "Juana Molina", headliningArtistId: 101)
        let jessica = Concert.stub(id: 2, startsOn: Self.saturdayNow, headliningArtistRaw: "Jessica Pratt", headliningArtistId: 102)

        let matches = ToursNearMeQuery.matchingConcerts(
            concerts: [juana, jessica],
            dateWindow: .tonight,
            likedArtists: [],
            now: Self.saturdayNow
        )

        #expect(matches.map(\.id).sorted() == [1, 2])
    }

    @Test("prefers the on-device loved intersection over the full date-filtered window")
    func prefersLovedIntersection() {
        let juana = Concert.stub(id: 1, startsOn: Self.saturdayNow, headliningArtistRaw: "Juana Molina", headliningArtistId: 101)
        let jessica = Concert.stub(id: 2, startsOn: Self.saturdayNow, headliningArtistRaw: "Jessica Pratt", headliningArtistId: 102)
        let liked = [LikedArtist(id: 101, name: "Juana Molina")]

        let matches = ToursNearMeQuery.matchingConcerts(
            concerts: [juana, jessica],
            dateWindow: .thisWeekend,
            likedArtists: liked,
            now: Self.saturdayNow
        )

        #expect(matches.map(\.id) == [1])
    }

    @Test("a liked artist outside the date window doesn't leak in, and the shelf falls back to the date-filtered set")
    func lovedMatchOutsideWindowDoesNotLeakIn() {
        let juana = Concert.stub(id: 1, startsOn: stationDay(2026, 8, 20, hour: 0), headliningArtistRaw: "Juana Molina", headliningArtistId: 101)
        let jessica = Concert.stub(id: 2, startsOn: Self.saturdayNow, headliningArtistRaw: "Jessica Pratt", headliningArtistId: 102)
        let liked = [LikedArtist(id: 101, name: "Juana Molina")]

        let matches = ToursNearMeQuery.matchingConcerts(
            concerts: [juana, jessica],
            dateWindow: .tonight,
            likedArtists: liked,
            now: Self.saturdayNow
        )

        // Juana's show is outside `.tonight`, so the loved tier is empty for
        // this window and the query falls back to the (Juana-less) date-filtered set.
        #expect(matches.map(\.id) == [2])
    }
}

@Suite("ToursNearMeQuery.resolve")
struct ToursNearMeQueryResolveTests {
    private static let now = stationDay(2026, 8, 1)

    @Test("resolves the fetched window to capped, matched ConcertEntity values")
    func resolvesMatchedEntities() async throws {
        let juana = Concert.stub(id: 1, startsOn: Self.now, headliningArtistRaw: "Juana Molina", headliningArtistId: 101)
        let jessica = Concert.stub(id: 2, startsOn: Self.now, headliningArtistRaw: "Jessica Pratt", headliningArtistId: 102)
        let fetcher = StubConcertsFetcher(pages: [
            ConcertsResponse(concerts: [juana, jessica], pagination: PaginationInfo(page: 1, limit: 100)),
        ])

        let matched = try await ToursNearMeQuery.resolve(
            fetcher: fetcher,
            dateWindow: .tonight,
            likedArtists: [],
            now: Self.now
        )

        #expect(matched.map(\.headlineName) == ["Juana Molina", "Jessica Pratt"])
    }

    @Test("caps the result to resultCap, keeping the soonest matches")
    func capsResults() async throws {
        let concerts = (0..<(ToursNearMeQuery.resultCap + 3)).map { offset in
            Concert.stub(
                id: offset,
                startsOn: Self.now,
                headliningArtistRaw: "Artist \(offset)",
                headliningArtistId: nil
            )
        }
        let fetcher = StubConcertsFetcher(pages: [
            ConcertsResponse(concerts: concerts, pagination: PaginationInfo(page: 1, limit: 100)),
        ])

        let matched = try await ToursNearMeQuery.resolve(
            fetcher: fetcher,
            dateWindow: .tonight,
            likedArtists: [],
            now: Self.now
        )

        #expect(matched.count == ToursNearMeQuery.resultCap)
        #expect(matched.map(\.headlineName) == concerts.prefix(ToursNearMeQuery.resultCap).map(\.headliningArtistRaw))
    }

    @Test("PRIVACY: the curated-window fetch is identical regardless of likedArtists")
    func fetchRequestIsIndependentOfLikedArtists() async throws {
        let fetcher = StubConcertsFetcher(pages: [
            ConcertsResponse(concerts: [], pagination: PaginationInfo(page: 1, limit: 100)),
        ])
        let tasteSignal = [
            LikedArtist(id: 101, name: "Juana Molina"),
            LikedArtist(id: 512, name: "Jessica Pratt"),
        ]

        _ = try await ToursNearMeQuery.resolve(fetcher: fetcher, dateWindow: .next7Days, likedArtists: [], now: Self.now)
        _ = try await ToursNearMeQuery.resolve(fetcher: fetcher, dateWindow: .next7Days, likedArtists: tasteSignal, now: Self.now)

        let requests = fetcher.requests
        #expect(requests.count == 2)
        // Same params both times -- proving the request the network actually
        // saw carries no trace of the second call's liked-artist set. No
        // liked-artist id/name ever appears in a `ConcertPageRequest` field:
        // there is no field for it to appear in.
        #expect(requests[0] == requests[1])
        #expect(requests[0].curated == true)
        #expect(requests[0].from == Self.now)
        #expect(requests[0].to == nil)
        #expect(requests[0].page == 1)
        #expect(requests[0].limit == ToursNearMeQuery.fetchLimit)
    }
}
