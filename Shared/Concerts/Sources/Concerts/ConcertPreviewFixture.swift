//
//  ConcertPreviewFixture.swift
//  Concerts
//
//  The canonical deterministic concert fixture primitives, plus the app-target
//  preview factory built on them.
//
//  Two things live here for two different reasons.
//
//  The primitives — ``Venue/catsCradle``, ``Concert/fixtureStartsOn``,
//  ``Concert/fixtureInstant(hour:minute:)``, and the ``Concert/fixtureId`` /
//  ``Concert/fixtureTicketURL`` / ``Concert/fixtureEventURL`` literals — are
//  declared in the shipping
//  `Concerts` module, ungated, and are the single definition of "the Cat's
//  Cradle fixture venue" and "the fixed 2026-08-01 station-zone fixture date"
//  for the whole repo. `ConcertsTesting`'s `Venue.stub()` / `Concert.stub()` /
//  `Concert.defaultStartsOn` / `Concert.stubInstant(hour:minute:)` all resolve
//  through them rather than restating them (#771 review: the first version of
//  this file duplicated all three byte-for-byte in a sibling target of the same
//  package, so a "dedup" slice took three copies to two).
//
//  The dependency can only run this way. `ConcertsTesting` depends on
//  `Concerts`, so `Concerts` cannot reach back into it — the shared definition
//  has to sit on this side of the edge. They are deliberately NOT `#if DEBUG`:
//  `ConcertsTesting` is a plain `.library` that any configuration may compile,
//  and gating them would make a release build of it fail to resolve its own
//  stubs. That is the same class of break that shipped in this slice's original
//  `BoxOfficeTicketView` preview extension. The cost is roughly twenty lines of
//  constant data in the release binary, which is the cheaper side of the trade.
//
//  ``Concert/previewFixture(id:venue:headliningArtistRaw:supportingArtistsRaw:doorsHour:showHour:ticketURL:eventURL:priceMin:priceMax:ageRestriction:status:artistBio:)``
//  is the part that stays `#if DEBUG`: it exists for the three app-target
//  `#Preview`/mock call sites (`BoxOfficeTicketView`, `UpcomingShowProvider`,
//  `ConcertDetailView`) that each used to hand-roll the same magic date and
//  venue literal. Those call sites compile into the app target, which does not
//  link `ConcertsTesting` — every consumer of that product is a `.testTarget`,
//  and it should stay that way. See issue #771.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

extension Venue {
    /// Cat's Cradle — the fixture venue every preview, mock, and test stub
    /// builds against, so the (id, slug, name, city, state, address) literal is
    /// declared exactly once. `ConcertsTesting`'s `Venue.stub()` defaults read
    /// from here.
    public static let catsCradle = Venue(
        id: 3,
        slug: "cats-cradle",
        name: "Cat's Cradle",
        city: "Carrboro",
        state: "NC",
        address: "300 E Main St"
    )

    /// ``catsCradle`` with no street address — the shape the backend returns
    /// for a venue whose source carried none.
    ///
    /// Derived from ``catsCradle`` rather than restated, so there is still only
    /// one Cat's Cradle literal. It exists because the address is not cosmetic:
    /// `BoxOfficeTicketPresenter.venueLine` appends it when non-empty, and
    /// `ConcertDetailView`'s address line prefers `"<address> · <city>"` over
    /// city/state. The Box Office previews and the DEBUG mock ticket render
    /// the no-address layout, and consolidating them onto a single fixture
    /// venue would silently have changed what they show (#771 review).
    public static let catsCradleWithoutAddress = Venue(
        id: Venue.catsCradle.id,
        slug: Venue.catsCradle.slug,
        name: Venue.catsCradle.name,
        city: Venue.catsCradle.city,
        state: Venue.catsCradle.state,
        address: nil
    )
}

extension Concert {
    /// The fixed fixture date: 2026-08-01 00:00 in the station zone (EDT,
    /// UTC-4). Every preview, mock, and test stub pins `startsOn` here so
    /// date-dependent behavior is deterministic regardless of when or where the
    /// code runs.
    ///
    /// Spelled as an epoch rather than assembled from `DateComponents` so the
    /// declaration has no unreachable `??` branch to keep honest — the branch a
    /// component-built version needs is unobservable, which is how the epoch it
    /// fell back to went three days wrong (`1_785_898_800` is 2026-08-04 23:00
    /// EDT) in every hand-rolled copy it was pasted into. Built this way, a
    /// wrong epoch fails ``ConcertFixturePrimitiveTests`` immediately.
    public static let fixtureStartsOn = Date(timeIntervalSince1970: 1_785_556_800)

    /// The fixture concert's backend id. Shared with `ConcertsTesting`'s
    /// `Concert.stub()` so the literal is declared once.
    public static let fixtureId = 4821

    /// The fixture's direct ticket-seller link. Shared with `Concert.stub()`.
    public static let fixtureTicketURL = URL(string: "https://www.etix.com/ticket/p/jessica-pratt")

    /// The fixture's venue event-page link.
    ///
    /// Deliberately *not* shared with `Concert.stub()`, which defaults
    /// `eventURL` to `nil`: `BoxOfficeTicketPresenter.hasVenuePage` keys off
    /// this field, and the presenter suite depends on a default stub having no
    /// venue page. Previews want the opposite default so the venue-page button
    /// is exercised. `ConcertsTestingAgreementTests` pins the divergence rather
    /// than letting it drift unobserved.
    public static let fixtureEventURL = URL(string: "https://catscradle.com/event/jessica-pratt")

    /// An instant on ``fixtureStartsOn``'s day at a station-zone wall-clock
    /// `hour`/`minute`. Returns `nil` for a `nil` hour so a caller can express
    /// "no doors/show time" without a separate overload.
    public static func fixtureInstant(hour: Int?, minute: Int = 0) -> Date? {
        guard let hour else { return nil }
        var components = Calendar.wxycStation.dateComponents([.year, .month, .day], from: fixtureStartsOn)
        components.hour = hour
        components.minute = minute
        return Calendar.wxycStation.date(from: components)
    }
}

#if DEBUG
extension Concert {
    /// Builds a preview/mock concert at Cat's Cradle on the fixed fixture date.
    ///
    /// Defaults match `ConcertsTesting`'s `Concert.stub()` (Jessica Pratt, on
    /// sale, $22–25, 7 PM doors / 8 PM show, same id and ticket link) so an app
    /// preview and a test fixture read the same at a glance — both resolve
    /// through the same primitives above, so they cannot drift.
    /// ``Concert/fixtureEventURL`` is the one deliberate exception; see its
    /// declaration.
    ///
    /// This is the app-target-facing factory. Test code should use
    /// `Concert.stub()` from `ConcertsTesting` instead, which exposes the full
    /// model surface (`headliningArtistId`, `genres`, `stationRecommended`, …)
    /// that previews have no use for.
    ///
    /// - Parameter venue: Pass ``Venue/catsCradleWithoutAddress`` to render the
    ///   city/state-only layout; the street address changes both the Box Office
    ///   ticket's venue line and the detail view's address line.
    public static func previewFixture(
        id: Int = Concert.fixtureId,
        venue: Venue = .catsCradle,
        headliningArtistRaw: String = "Jessica Pratt",
        supportingArtistsRaw: [String] = ["Julie Byrne"],
        doorsHour: Int? = 19,
        showHour: Int? = 20,
        ticketURL: URL? = Concert.fixtureTicketURL,
        eventURL: URL? = Concert.fixtureEventURL,
        priceMin: Double? = 22,
        priceMax: Double? = 25,
        ageRestriction: String? = "All Ages",
        status: ShowStatus,
        artistBio: String? = nil
    ) -> Concert {
        Concert(
            id: id,
            venue: venue,
            startsOn: fixtureStartsOn,
            startsAt: fixtureInstant(hour: showHour),
            doorsAt: fixtureInstant(hour: doorsHour),
            headliningArtistRaw: headliningArtistRaw,
            supportingArtistsRaw: supportingArtistsRaw,
            ticketURL: ticketURL,
            eventURL: eventURL,
            priceMin: priceMin,
            priceMax: priceMax,
            ageRestriction: ageRestriction,
            status: status,
            artistBio: artistBio
        )
    }
}
#endif
