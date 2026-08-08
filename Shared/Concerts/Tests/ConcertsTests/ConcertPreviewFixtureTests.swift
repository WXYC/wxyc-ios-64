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
//  `ConcertsTestingAgreementTests` in the middle is the load-bearing one: it
//  asserts the `ConcertsTesting` stub vocabulary and the `Concerts` fixture
//  vocabulary resolve to identical values, field by field — including the `id`
//  and `ticketURL` literals the two used to spell separately, and the single
//  field (`eventURL`) they deliberately disagree on. The first version of this
//  slice declared both vocabularies independently, byte-for-byte, in sibling
//  targets of one package — a dedup that took three copies to two. Delegation
//  alone doesn't prevent that returning; this test does.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import ConcertsTesting
@testable import Concerts

/// Every readback below decomposes through this literal rather than
/// `Calendar.wxycStation`. The fixture instants are *built* through that
/// constant, so reading them back through it too would be a round trip that
/// holds for any zone it names; the literal is what pins the fixture to a
/// specific wall-clock day and hour (#771 review).
private let eastern: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
    return calendar
}()

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

    /// The no-address variant is derived, so every field but `address` has to
    /// track ``Venue/catsCradle`` — restating it as a second literal is exactly
    /// the divergence this fixture exists to prevent.
    @Test
    func catsCradleWithoutAddressDiffersOnlyInItsAddress() {
        let full = Venue.catsCradle
        let bare = Venue.catsCradleWithoutAddress
        #expect(bare.address == nil)
        #expect(bare.id == full.id)
        #expect(bare.slug == full.slug)
        #expect(bare.name == full.name)
        #expect(bare.city == full.city)
        #expect(bare.state == full.state)
    }

    /// `fixtureStartsOn` is a bare epoch, so this is the only thing standing
    /// between it and a wrong instant — and it caught one: `1_785_898_800`
    /// (2026-08-04 23:00 EDT) was pasted into every hand-rolled copy of this
    /// date before the fixture was shared.
    @Test
    func fixtureStartsOnIsMidnightAugustFirst2026InTheStationZone() {
        let components = eastern.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Concert.fixtureStartsOn
        )
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 1)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
    }

    @Test
    func fixtureInstantReturnsNilForANilHour() {
        #expect(Concert.fixtureInstant(hour: nil) == nil)
    }

    @Test
    func fixtureInstantBuildsTheGivenStationZoneHour() throws {
        let instant = try #require(Concert.fixtureInstant(hour: 19, minute: 30))
        #expect(eastern.component(.hour, from: instant) == 19)
        #expect(eastern.component(.minute, from: instant) == 30)
        #expect(eastern.component(.day, from: instant) == 1)
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
        #expect(stub.id == preview.id)
        #expect(stub.venue == preview.venue)
        #expect(stub.startsOn == preview.startsOn)
        #expect(stub.startsAt == preview.startsAt)
        #expect(stub.doorsAt == preview.doorsAt)
        #expect(stub.headliningArtistRaw == preview.headliningArtistRaw)
        #expect(stub.supportingArtistsRaw == preview.supportingArtistsRaw)
        #expect(stub.ticketURL == preview.ticketURL)
        #expect(stub.priceMin == preview.priceMin)
        #expect(stub.priceMax == preview.priceMax)
        #expect(stub.ageRestriction == preview.ageRestriction)
        #expect(stub.status == preview.status)
    }

    /// `eventURL` is the one field the two vocabularies deliberately disagree
    /// on, and the reason is load-bearing: `BoxOfficeTicketPresenter`'s suite
    /// depends on a default stub having no venue page, while previews want the
    /// venue-page button exercised. Asserted rather than left implicit so the
    /// divergence is a decision on the record instead of drift nobody sees —
    /// the earlier version of this suite skipped `eventURL` entirely, and the
    /// factory's doc comment claimed agreement it did not have.
    @Test("eventURL is the one deliberate disagreement, and it is exactly that")
    func stubHasNoVenuePageButThePreviewFixtureDoes() {
        #expect(Concert.stub().eventURL == nil)
        #expect(Concert.previewFixture(status: .onSale).eventURL == Concert.fixtureEventURL)
        #expect(Concert.fixtureEventURL != nil)
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
        #expect(concert.doorsAt.map { eastern.component(.hour, from: $0) } == 19)
        #expect(concert.startsAt.map { eastern.component(.hour, from: $0) } == 20)
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

    /// The Box Office previews and the DEBUG mock ticket pass this venue, and
    /// the address is not cosmetic at either site — see
    /// ``Venue/catsCradleWithoutAddress``.
    @Test
    func theVenueOverrideReachesTheBuiltConcert() {
        let concert = Concert.previewFixture(venue: .catsCradleWithoutAddress, status: .onSale)
        #expect(concert.venue.address == nil)
        #expect(concert.venue.name == "Cat's Cradle")
    }
}
