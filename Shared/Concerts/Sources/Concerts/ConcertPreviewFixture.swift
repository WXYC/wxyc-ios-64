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
//  ``Concert/fixtureInstant(hour:minute:)`` — are declared in the shipping
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
//  ``Concert/previewFixture(id:headliningArtistRaw:supportingArtistsRaw:doorsHour:showHour:ticketURL:eventURL:priceMin:priceMax:ageRestriction:status:artistBio:)``
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
}

extension Concert {
    /// The fixed fixture date: 2026-08-01 in the station zone. Every preview,
    /// mock, and test stub pins `startsOn` here so date-dependent behavior is
    /// deterministic regardless of when or where the code runs.
    ///
    /// The `?? Date(timeIntervalSince1970:)` fallback is unreachable for these
    /// fixed components but keeps the declaration force-unwrap-free.
    public static let fixtureStartsOn: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        let components = DateComponents(year: 2026, month: 8, day: 1)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_785_898_800)
    }()

    /// An instant on ``fixtureStartsOn``'s day at a station-zone wall-clock
    /// `hour`/`minute`. Returns `nil` for a `nil` hour so a caller can express
    /// "no doors/show time" without a separate overload.
    public static func fixtureInstant(hour: Int?, minute: Int = 0) -> Date? {
        guard let hour else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        var components = calendar.dateComponents([.year, .month, .day], from: fixtureStartsOn)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }
}

#if DEBUG
extension Concert {
    /// Builds a preview/mock concert at Cat's Cradle on the fixed fixture date.
    ///
    /// Defaults match `ConcertsTesting`'s `Concert.stub()` (Jessica Pratt, on
    /// sale, $22–25, 7 PM doors / 8 PM show) so an app preview and a test
    /// fixture read the same at a glance — both now resolve their venue and
    /// dates through the same primitives above, so they cannot drift.
    ///
    /// This is the app-target-facing factory. Test code should use
    /// `Concert.stub()` from `ConcertsTesting` instead, which exposes the full
    /// model surface (`headliningArtistId`, `genres`, `stationRecommended`, …)
    /// that previews have no use for.
    public static func previewFixture(
        id: Int = 4821,
        headliningArtistRaw: String = "Jessica Pratt",
        supportingArtistsRaw: [String] = ["Julie Byrne"],
        doorsHour: Int? = 19,
        showHour: Int? = 20,
        ticketURL: URL? = URL(string: "https://www.etix.com/ticket/p/jessica-pratt"),
        eventURL: URL? = URL(string: "https://catscradle.com/event/jessica-pratt"),
        priceMin: Double? = 22,
        priceMax: Double? = 25,
        ageRestriction: String? = "All Ages",
        status: ShowStatus,
        artistBio: String? = nil
    ) -> Concert {
        Concert(
            id: id,
            venue: .catsCradle,
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
