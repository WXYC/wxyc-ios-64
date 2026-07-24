//
//  AddConcertToCalendarQueryTests.swift
//  WXYCIntents
//
//  Verifies AddConcertToCalendarQuery.resolveAndSave maps a resolved Concert
//  to the correct ConcertCalendarEvent fields and saves it through the
//  injected CalendarEventSaving seam — no EventKit or real calendar access
//  involved — and that a denied-access, save-failure, or unresolvable-concert
//  path returns a clear `Outcome` rather than throwing or attempting a save
//  (#630). Plain stub/spy injection, no `@Dependency`/`AppDependencyManager`
//  needed: see `AddConcertToCalendarQuery`'s header for why the seams are
//  explicit parameters rather than `@Dependency` properties.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import ConcertsTesting
import Foundation
import Testing
@testable import WXYCIntents

@Suite("AddConcertToCalendarQuery.resolveAndSave")
struct AddConcertToCalendarQueryTests {
    @Test("maps the resolved concert to the correct ConcertCalendarEvent and saves it")
    func resolvesMapsAndSaves() async throws {
        let concert = Concert.stub(id: 4821, headliningArtistRaw: "Jessica Pratt")
        let fetcher = StubConcertsFetcher(pages: [], concertsByID: [4821: concert])
        let store = SpyCalendarEventSaving(accessGranted: true)

        let outcome = await AddConcertToCalendarQuery.resolveAndSave(
            concertID: 4821,
            fetcher: fetcher,
            calendarStore: store
        )

        #expect(outcome == .added(ConcertCalendarEvent(concert)))
        #expect(store.savedEvent == ConcertCalendarEvent(concert))
    }

    @Test("maps a doors-only concert to an all-day ConcertCalendarEvent")
    func resolvesAllDayConcert() async throws {
        let concert = Concert.stub(id: 77, startsAt: nil, doorsAt: nil)
        let fetcher = StubConcertsFetcher(pages: [], concertsByID: [77: concert])
        let store = SpyCalendarEventSaving(accessGranted: true)

        let outcome = await AddConcertToCalendarQuery.resolveAndSave(
            concertID: 77,
            fetcher: fetcher,
            calendarStore: store
        )

        guard case .added(let calendarEvent) = outcome else {
            Issue.record("Expected .added, got \(outcome)")
            return
        }
        #expect(calendarEvent.isAllDay == true)
    }

    @Test("returns .accessDenied and does not save when calendar access is declined")
    func deniedAccessDoesNotSave() async throws {
        let concert = Concert.stub(id: 4821)
        let fetcher = StubConcertsFetcher(pages: [], concertsByID: [4821: concert])
        let store = SpyCalendarEventSaving(accessGranted: false)

        let outcome = await AddConcertToCalendarQuery.resolveAndSave(
            concertID: 4821,
            fetcher: fetcher,
            calendarStore: store
        )

        #expect(outcome == .accessDenied)
        #expect(store.savedEvent == nil)
    }

    @Test("returns .concertUnavailable and does not request access when the concert can't be resolved")
    func unresolvableConcertDoesNotSave() async throws {
        let fetcher = StubConcertsFetcher(pages: [], concertsByID: [:])
        let store = SpyCalendarEventSaving(accessGranted: true)

        let outcome = await AddConcertToCalendarQuery.resolveAndSave(
            concertID: 999,
            fetcher: fetcher,
            calendarStore: store
        )

        #expect(outcome == .concertUnavailable)
        #expect(store.savedEvent == nil)
        #expect(store.requestAccessCallCount == 0)
    }

    @Test("returns .saveFailed with the mapped title when the save itself throws")
    func saveFailurePropagatesTitle() async throws {
        let concert = Concert.stub(id: 4821, headliningArtistRaw: "Jessica Pratt")
        let fetcher = StubConcertsFetcher(pages: [], concertsByID: [4821: concert])
        let store = SpyCalendarEventSaving(accessGranted: true, saveError: SpyCalendarEventSaving.SaveError.boom)

        let outcome = await AddConcertToCalendarQuery.resolveAndSave(
            concertID: 4821,
            fetcher: fetcher,
            calendarStore: store
        )

        #expect(outcome == .saveFailed(title: "Jessica Pratt"))
    }
}

/// Records the `ConcertCalendarEvent` passed to `save(_:)` (`nil` if never
/// called), counts `requestAccess()` calls, and returns canned results, so
/// tests can assert `AddConcertToCalendarQuery`'s mapping and permission
/// handling without EventKit. A plain `@unchecked Sendable` class, mirroring
/// `MockStructuredAnalytics` — tests drive `resolveAndSave` sequentially, so
/// no locking is needed.
final class SpyCalendarEventSaving: CalendarEventSaving, @unchecked Sendable {
    enum SaveError: Error {
        case boom
    }

    private let accessGranted: Bool
    private let saveError: (any Error)?
    private(set) var savedEvent: ConcertCalendarEvent?
    private(set) var requestAccessCallCount = 0

    init(accessGranted: Bool, saveError: (any Error)? = nil) {
        self.accessGranted = accessGranted
        self.saveError = saveError
    }

    func requestAccess() async -> Bool {
        requestAccessCallCount += 1
        return accessGranted
    }

    func save(_ calendarEvent: ConcertCalendarEvent) throws {
        if let saveError {
            throw saveError
        }
        savedEvent = calendarEvent
    }
}
