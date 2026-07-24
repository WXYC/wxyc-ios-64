//
//  CalendarEventSaving.swift
//  Intents
//
//  The EventKit seam `AddConcertToCalendarIntent` (#630) writes through --
//  write-only calendar access plus a save -- abstracted so the intent is
//  unit-testable without touching the real calendar. `EventKitCalendarEventSaving`
//  is the production conformer; tests use a recording spy, mirroring
//  `ConcertReindexer`'s protocol/production-conformer split.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts

/// Requests write-only calendar access and saves a mapped ``ConcertCalendarEvent``.
public protocol CalendarEventSaving: Sendable {
    /// Requests add-only calendar access (EventKit's
    /// `requestWriteOnlyAccessToEvents`), mirroring `ConcertCalendarSheet`'s
    /// in-app request. Returns `false` on denial or any error rather than
    /// throwing, so the intent's permission check is a single boolean branch.
    func requestAccess() async -> Bool

    /// Creates and saves a calendar event from `calendarEvent`'s fields.
    func save(_ calendarEvent: ConcertCalendarEvent) throws
}
