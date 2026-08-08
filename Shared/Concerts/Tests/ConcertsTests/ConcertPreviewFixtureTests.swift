//
//  ConcertPreviewFixtureTests.swift
//  Concerts
//
//  Guards the canonical fixture primitives (`Venue.catsCradle`,
//  `Concert.fixtureStartsOn`, `Concert.fixtureInstant`) and the `#if DEBUG`
//  app-target factory built on them (`Concert.previewFixture`), which together
//  replaced three hand-rolled copies of the same magic date and Cat's Cradle
//  venue literal across `BoxOfficeTicketView`, `UpcomingShowProvider`, and
//  `ConcertDetailView` (issue #771).
//
//  `ConcertsTestingAgreementTests` at the bottom is the load-bearing one: it
//  asserts the `ConcertsTesting` stub vocabulary and the `Concerts` fixture
//  vocabulary resolve to identical values. The first version of this slice
//  declared both independently, byte-for-byte, in sibling targets of one
//  package — a dedup that took three copies to two. Delegation alone doesn't
//  prevent that returning; this test does.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import ConcertsTesting
@testable import Concerts

@Suite("Concert fixture primitives")
struct ConcertFixturePrimitiveTests {
    @Test
    func catsCradleIsTheCanonicalVenue() {
        let venue = Venue.catsCradle
        #expect(venue.id == 3)
        #expect(venue.slug == "cats-cradle")
        #expect(venue.name == "Cat's Cradle")
        #expect(venue.city == "Carrboro")
        #expect(venue.state == "NC")
        #expect(venue.address == "300 E Main St")
    }

    @Test
    func fixtureStartsOnIsAugustFirst2026InTheStationZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        let components = calendar.dateComponents([.year, .month, .day], from: Concert.fixtureStartsOn)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 1)
    }

    /// The `??` branch in `fixtureStartsOn` is unreachable for fixed components,
    /// so nothing else observes the epoch it falls back to — which is exactly how
    /// it went three days wrong and got copied to every hand-rolled call site.
    /// Naming the constant is what makes it assertable.
    @Test
    func theUnreachableEpochFallbackNamesTheSameInstantAsTheComponents() {
        #expect(Concert.fixtureStartsOnFallback == Concert.fixtureStartsOn)
    }

    @Test
    func fixtureInstantReturnsNilForANilHour() {
        #expect(Concert.fixtureInstant(hour: nil) == nil)
    }

    @Test
    func fixtureInstantBuildsTheGivenStationZoneHour() throws {
        let instant = try #require(Concert.fixtureInstant(hour: 19))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        #expect(calendar.component(.hour, from: instant) == 19)
        #expect(calendar.component(.day, from: instant) == 1)
    }
}

/// The anti-redivergence net. If someone reintroduces an independent copy of
/// the venue or the date in either target, these fail.
@Suite("Concerts and ConcertsTesting agree on the fixtures")
struct ConcertsTestingAgreementTests {
    @Test("the stub venue is the canonical fixture venue")
    func stubVenueMatchesCanonical() {
        #expect(Venue.stub() == Venue.catsCradle)
    }

    @Test("defaultStartsOn is fixtureStartsOn")
    func defaultStartsOnMatchesCanonical() {
        #expect(Concert.defaultStartsOn == Concert.fixtureStartsOn)
    }

    @Test("stubInstant and fixtureInstant agree", arguments: [nil, 0, 9, 19, 20, 23])
    func stubInstantMatchesFixtureInstant(hour: Int?) {
        #expect(Concert.stubInstant(hour: hour) == Concert.fixtureInstant(hour: hour))
    }

    @Test("a default stub and a default preview fixture describe the same show")
    func stubAndPreviewFixtureAgree() {
        let stub = Concert.stub()
        let preview = Concert.previewFixture(status: .onSale)
        #expect(stub.venue == preview.venue)
        #expect(stub.startsOn == preview.startsOn)
        #expect(stub.startsAt == preview.startsAt)
        #expect(stub.doorsAt == preview.doorsAt)
        #expect(stub.headliningArtistRaw == preview.headliningArtistRaw)
        #expect(stub.supportingArtistsRaw == preview.supportingArtistsRaw)
        #expect(stub.priceMin == preview.priceMin)
        #expect(stub.priceMax == preview.priceMax)
        #expect(stub.ageRestriction == preview.ageRestriction)
        #expect(stub.status == preview.status)
    }
}

@Suite("Concert preview fixture")
struct ConcertPreviewFixtureTests {
    @Test
    func defaultFixtureMatchesTheJessicaPrattAtCatsCradleConvention() {
        let concert = Concert.previewFixture(status: .onSale)
        #expect(concert.venue == .catsCradle)
        #expect(concert.startsOn == Concert.fixtureStartsOn)
        #expect(concert.headliningArtistRaw == "Jessica Pratt")
        #expect(concert.supportingArtistsRaw == ["Julie Byrne"])
        #expect(concert.priceMin == 22)
        #expect(concert.priceMax == 25)
        #expect(concert.ageRestriction == "All Ages")
        #expect(concert.status == .onSale)
        // 7 PM doors / 8 PM show, station zone.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        #expect(concert.doorsAt.map { calendar.component(.hour, from: $0) } == 19)
        #expect(concert.startsAt.map { calendar.component(.hour, from: $0) } == 20)
    }

    @Test
    func fixtureOverridesFlowThroughToTheBuiltConcert() {
        let concert = Concert.previewFixture(
            id: 900_042,
            headliningArtistRaw: "Nilüfer Yanya",
            supportingArtistsRaw: ["Tapir!"],
            doorsHour: nil,
            showHour: nil,
            status: .soldOut,
            artistBio: "Placeholder bio"
        )
        #expect(concert.id == 900_042)
        #expect(concert.headliningArtistRaw == "Nilüfer Yanya")
        #expect(concert.supportingArtistsRaw == ["Tapir!"])
        #expect(concert.doorsAt == nil)
        #expect(concert.startsAt == nil)
        #expect(concert.status == .soldOut)
        #expect(concert.artistBio == "Placeholder bio")
    }
}
