//
//  ConcertPreviewFixtureTests.swift
//  Concerts
//
//  Guards the app-target preview-fixture factory (`Concert.previewFixture`,
//  `Venue.previewCatsCradle`) that replaced three hand-rolled copies of the
//  same magic date and Cat's Cradle venue literal across `BoxOfficeTicketView`,
//  `UpcomingShowProvider`, and `ConcertDetailView` (issue #771). `#if DEBUG`-gated,
//  same as the factory itself, since it doesn't exist in a release build.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if DEBUG
import Foundation
import Testing
@testable import Concerts

@Suite("Concert preview fixture")
struct ConcertPreviewFixtureTests {
    @Test
    func previewCatsCradleIsTheCanonicalVenue() {
        let venue = Venue.previewCatsCradle
        #expect(venue.id == 3)
        #expect(venue.slug == "cats-cradle")
        #expect(venue.name == "Cat's Cradle")
        #expect(venue.city == "Carrboro")
        #expect(venue.state == "NC")
        #expect(venue.address == "300 E Main St")
    }

    @Test
    func previewStartsOnIsAugustFirst2026InTheStationZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        let components = calendar.dateComponents([.year, .month, .day], from: Concert.previewStartsOn)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 1)
    }

    @Test
    func previewInstantReturnsNilForANilHour() {
        #expect(Concert.previewInstant(hour: nil) == nil)
    }

    @Test
    func previewInstantBuildsTheGivenStationZoneHour() throws {
        let instant = try #require(Concert.previewInstant(hour: 19))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        #expect(calendar.component(.hour, from: instant) == 19)
        #expect(calendar.component(.day, from: instant) == 1)
    }

    @Test
    func defaultFixtureMatchesTheJessicaPrattAtCatsCradleConvention() {
        let concert = Concert.previewFixture(status: .onSale)
        #expect(concert.venue == .previewCatsCradle)
        #expect(concert.startsOn == Concert.previewStartsOn)
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
#endif
