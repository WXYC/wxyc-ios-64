//
//  ConcertPreviewFixture.swift
//  Concerts
//
//  The one Cat's Cradle preview/mock concert factory behind three app-target
//  call sites that used to each hand-roll the identical magic date
//  (2026-08-01, epoch fallback 1_785_898_800, 19:00/20:00-hour doors/show) and
//  the identical `Venue(id: 3, slug: "cats-cradle", ...)` literal:
//  `BoxOfficeTicketView`'s `Concert.preview`, `UpcomingShowProvider`'s
//  `DebugUpcomingShowResolver.mockShow`, and `ConcertDetailView`'s
//  `Concert.detailPreview`. See issue #771.
//
//  `#if DEBUG`-gated and declared in the shipping `Concerts` module — not
//  `ConcertsTesting` — because a SwiftUI `#Preview` body compiles into the app
//  target, which can't link a test-support product. `ConcertsTesting`'s own
//  `Concert.stub()`/`Venue.stub()` remain the sibling for XCTest/Swift Testing
//  code; the two factories rhyme by design (same "WXYC-canonical touring
//  artist at a real venue" convention, see `docs/test-fixtures.md`) but serve
//  different linkage constraints, so they stay separate rather than one
//  reaching across the module boundary the other exists to respect.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

#if DEBUG
extension Venue {
    /// Cat's Cradle — the venue every app-target preview/mock concert builds
    /// against, so the literal (id, slug, address) is declared exactly once.
    public static let previewCatsCradle = Venue(
        id: 3,
        slug: "cats-cradle",
        name: "Cat's Cradle",
        city: "Carrboro",
        state: "NC",
        address: "300 E Main St"
    )
}

extension Concert {
    /// The fixed preview date (2026-08-01, station zone) every app-target
    /// preview/mock concert pins `startsOn` to. Falls back to a fixed epoch
    /// offset so the declaration stays force-unwrap-free.
    public static let previewStartsOn: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        let components = DateComponents(year: 2026, month: 8, day: 1)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_785_898_800)
    }()

    /// An instant on ``previewStartsOn``'s day at a station-zone wall-clock
    /// `hour`/`minute`. Returns `nil` for a `nil` hour so a caller can express
    /// "no doors/show time".
    public static func previewInstant(hour: Int?, minute: Int = 0) -> Date? {
        guard let hour else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        var components = calendar.dateComponents([.year, .month, .day], from: previewStartsOn)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    /// Builds a preview/mock concert at Cat's Cradle on the fixed preview
    /// date. Defaults mirror `ConcertsTesting`'s `Concert.stub()` (Jessica
    /// Pratt, on sale, $22–25, 7 PM doors / 8 PM show) so the app-target
    /// previews and the test fixtures read the same at a glance.
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
            venue: .previewCatsCradle,
            startsOn: previewStartsOn,
            startsAt: previewInstant(hour: showHour),
            doorsAt: previewInstant(hour: doorsHour),
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
