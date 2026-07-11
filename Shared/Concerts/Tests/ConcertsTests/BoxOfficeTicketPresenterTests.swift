//
//  BoxOfficeTicketPresenterTests.swift
//  Concerts
//
//  Tests for the pure presentation logic behind the Box Office ticket: date/time
//  labels, price formatting, and the per-status pill / CTA / caption copy. The
//  copy mirrors the approved prototype
//  (docs/ideas/touring-shows-box-office.html).
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Concerts
import ConcertsTesting

@Suite("BoxOfficeTicketPresenter")
struct BoxOfficeTicketPresenterTests {

    // MARK: - Date

    @Test("Formats the date as a station-zone weekday label")
    func formatsDateLabel() {
        // Stub default is 2026-08-01 (a Saturday, station zone).
        let presenter = BoxOfficeTicketPresenter(.stub())
        #expect(presenter.dateLabel == "Sat, Aug 1")
        #expect(presenter.compactDateLabel == "SAT AUG 1")
    }

    @Test("Splits the date for the ticket stub's date block")
    func stubDateParts() {
        // Stub default is 2026-08-01 (Saturday, station zone).
        let presenter = BoxOfficeTicketPresenter(.stub())
        #expect(presenter.stubWeekday == "SAT")
        #expect(presenter.stubDayNumber == "1")
        #expect(presenter.stubMonth == "AUG")
    }

    @Test("Derives a stable faux ticket serial from the concert id")
    func ticketSerial() {
        #expect(BoxOfficeTicketPresenter(.stub(id: 4821)).ticketSerial == "WX-4821")
        #expect(BoxOfficeTicketPresenter(.stub(id: 12)).ticketSerial == "WX-12")
    }

    // MARK: - Time

    @Test("Composes doors + show into one time label")
    func composesDoorsAndShow() {
        let presenter = BoxOfficeTicketPresenter(
            .stub(startsAt: Concert.stubInstant(hour: 20), doorsAt: Concert.stubInstant(hour: 19))
        )
        #expect(presenter.timeLabel == "Doors 7 PM · Show 8 PM")
    }

    @Test("Shows only the set time when doors is absent")
    func showTimeOnly() {
        let presenter = BoxOfficeTicketPresenter(
            .stub(startsAt: Concert.stubInstant(hour: 20), doorsAt: nil)
        )
        #expect(presenter.timeLabel == "Show 8 PM")
    }

    @Test("Shows only doors when the set time is absent")
    func doorsTimeOnly() {
        let presenter = BoxOfficeTicketPresenter(
            .stub(startsAt: nil, doorsAt: Concert.stubInstant(hour: 19))
        )
        #expect(presenter.timeLabel == "Doors 7 PM")
    }

    @Test("Includes minutes when the time is not on the hour")
    func includesMinutes() {
        let presenter = BoxOfficeTicketPresenter(
            .stub(startsAt: Concert.stubInstant(hour: 20, minute: 30), doorsAt: nil)
        )
        #expect(presenter.timeLabel == "Show 8:30 PM")
    }

    @Test("Time label is nil when neither time is present")
    func noTimeLabel() {
        let presenter = BoxOfficeTicketPresenter(.stub(startsAt: nil, doorsAt: nil))
        #expect(presenter.timeLabel == nil)
    }

    @Test("Exposes doors and show times individually for stat cells")
    func individualTimeLabels() {
        let presenter = BoxOfficeTicketPresenter(
            .stub(startsAt: Concert.stubInstant(hour: 20, minute: 30), doorsAt: Concert.stubInstant(hour: 19))
        )
        #expect(presenter.doorsLabel == "7 PM")
        #expect(presenter.showLabel == "8:30 PM")
    }

    @Test("Individual time labels are nil when absent")
    func individualTimeLabelsNil() {
        let presenter = BoxOfficeTicketPresenter(.stub(startsAt: nil, doorsAt: nil))
        #expect(presenter.doorsLabel == nil)
        #expect(presenter.showLabel == nil)
    }

    // MARK: - Price

    @Test("Renders a price range with an en dash")
    func priceRange() {
        let presenter = BoxOfficeTicketPresenter(.stub(priceMin: 22, priceMax: 25, status: .onSale))
        #expect(presenter.priceLabel == "$22–$25")
    }

    @Test("Renders a single price when min equals max")
    func singlePrice() {
        let presenter = BoxOfficeTicketPresenter(.stub(priceMin: 22, priceMax: 22, status: .onSale))
        #expect(presenter.priceLabel == "$22")
    }

    @Test("Renders a single price when only the minimum is known")
    func onlyMinPrice() {
        let presenter = BoxOfficeTicketPresenter(.stub(priceMin: 20, priceMax: nil, status: .onSale))
        #expect(presenter.priceLabel == "$20")
    }

    @Test("Renders \"Free\" for a free show regardless of price fields")
    func freePrice() {
        let presenter = BoxOfficeTicketPresenter(.stub(priceMin: nil, priceMax: nil, status: .free))
        #expect(presenter.priceLabel == "Free")
    }

    @Test("Renders \"Free\" for the wire's free signal (price_min == 0, non-free status)")
    func freePriceFromZeroMinimum() {
        // The backend Concert status enum has no `free` value; a genuinely-free
        // show arrives as e.g. {status: "on_sale", price_min: 0}. Must read "Free",
        // not "$0".
        let presenter = BoxOfficeTicketPresenter(.stub(priceMin: 0, priceMax: 0, status: .onSale))
        #expect(presenter.priceLabel == "Free")
    }

    @Test("A zero-floor priced range is not collapsed to \"Free\"")
    func zeroFloorRangeKeepsUpperBound() {
        let presenter = BoxOfficeTicketPresenter(.stub(priceMin: 0, priceMax: 25, status: .onSale))
        #expect(presenter.priceLabel == "$0–$25")
    }

    @Test("Price label is nil when unpriced and not free")
    func noPrice() {
        let presenter = BoxOfficeTicketPresenter(.stub(priceMin: nil, priceMax: nil, status: .onSale))
        #expect(presenter.priceLabel == nil)
    }

    @Test("Keeps cents when a price is not a whole dollar")
    func priceWithCents() {
        let presenter = BoxOfficeTicketPresenter(.stub(priceMin: 12.5, priceMax: 12.5, status: .onSale))
        #expect(presenter.priceLabel == "$12.50")
    }

    // MARK: - Status pill

    @Test("Maps status to pill text", arguments: [
        (ShowStatus.onSale, "On Sale"),
        (.soldOut, "Sold Out"),
        (.cancelled, "Cancelled"),
        (.rescheduled, "Rescheduled"),
        (.free, "Free"),
    ])
    func statusPill(status: ShowStatus, expected: String) {
        #expect(BoxOfficeTicketPresenter(.stub(status: status)).statusPillText == expected)
    }

    @Test("Unknown status shows no pill")
    func unknownNoPill() {
        #expect(BoxOfficeTicketPresenter(.stub(status: .unknown)).statusPillText == nil)
    }

    @Test("isCancelled is true only for the cancelled status")
    func isCancelledFlag() {
        #expect(BoxOfficeTicketPresenter(.stub(status: .cancelled)).isCancelled == true)
        #expect(BoxOfficeTicketPresenter(.stub(status: .onSale)).isCancelled == false)
    }

    // MARK: - CTA label

    @Test("Maps status to CTA label", arguments: [
        (ShowStatus.onSale, "Get Tickets"),
        (.free, "RSVP"),
        (.soldOut, "See Venue Page"),
        (.rescheduled, "Get Tickets"),
        (.cancelled, "See the venue's page"),
        (.unknown, "See Venue Page"),
    ])
    func ctaLabel(status: ShowStatus, expected: String) {
        #expect(BoxOfficeTicketPresenter(.stub(status: status)).ctaLabel == expected)
    }

    // MARK: - CTA caption (venue-aware)

    @Test("On-sale caption names the venue")
    func onSaleCaption() {
        let presenter = BoxOfficeTicketPresenter(.stub(venue: .stub(name: "Cat's Cradle"), status: .onSale))
        #expect(presenter.ctaCaption == "Opens Cat's Cradle's event page")
    }

    @Test("Sold-out caption names the venue and hints at holds")
    func soldOutCaption() {
        let presenter = BoxOfficeTicketPresenter(.stub(venue: .stub(name: "Cat's Cradle"), status: .soldOut))
        #expect(presenter.ctaCaption == "Sold out here — Cat's Cradle sometimes releases more.")
    }

    @Test("Cancelled caption states the cancellation")
    func cancelledCaption() {
        let presenter = BoxOfficeTicketPresenter(.stub(status: .cancelled))
        #expect(presenter.ctaCaption == "This show has been cancelled.")
    }

    @Test("Caption names whichever venue the concert carries")
    func captionNamesGivenVenue() {
        // The backend `Venue.name` is always present, so the presenter always
        // names it — there is no "the venue" fallback (the old triangle-shows
        // `venue_name` was optional; the backend `Concert.venue` is not).
        let presenter = BoxOfficeTicketPresenter(.stub(venue: .stub(name: "Local 506"), status: .onSale))
        #expect(presenter.ctaCaption == "Opens Local 506's event page")
    }

    // MARK: - Feed tag + CTA URL

    @Test("Maps status to the compact feed-row tag", arguments: [
        (ShowStatus.onSale, "Tickets"),
        (.soldOut, "Sold Out"),
        (.cancelled, "Cancelled"),
        (.rescheduled, "Rescheduled"),
        (.free, "Free · RSVP"),
    ])
    func feedTag(status: ShowStatus, expected: String) {
        #expect(BoxOfficeTicketPresenter(.stub(status: status)).feedTagText == expected)
    }

    @Test("Exposes the concert's CTA URL (the ticket link)")
    func exposesCTAURL() {
        let url = URL(string: "https://www.etix.com/ticket/p/x")
        let presenter = BoxOfficeTicketPresenter(.stub(ticketURL: url))
        #expect(presenter.ctaURL == url)
    }

    @Test("Maps status to the feed-row tag style", arguments: [
        (ShowStatus.onSale, FeedTagStyle.prominent),
        (.free, .free),
        (.soldOut, .muted),
        (.cancelled, .negative),
        (.rescheduled, .neutral),
        (.unknown, .neutral),
    ])
    func feedTagStyle(status: ShowStatus, expected: FeedTagStyle) {
        #expect(BoxOfficeTicketPresenter(.stub(status: status)).feedTagStyle == expected)
    }
}
