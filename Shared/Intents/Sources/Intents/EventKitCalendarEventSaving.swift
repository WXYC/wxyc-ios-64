//
//  EventKitCalendarEventSaving.swift
//  Intents
//
//  Production `CalendarEventSaving`, backed by a fresh `EKEventStore` per
//  call -- App Intents run in a separate, short-lived process, so there's no
//  long-lived store worth holding onto across invocations, the same
//  one-store-per-operation shape `ConcertCalendarSheet` uses for its in-app
//  "Add to Calendar" sheet (#538). Requests write-only access
//  (`requestWriteOnlyAccessToEvents`) -- the app only ever adds events here,
//  never reads the calendar -- and saves the event directly rather than
//  presenting `EKEventEditViewController`: Siri/Spotlight can't host that
//  UIKit editor, so this headless path has no user-confirmation step (#630).
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import EventKit
import Foundation

public struct EventKitCalendarEventSaving: CalendarEventSaving {
    public init() {}

    public func requestAccess() async -> Bool {
        (try? await EKEventStore().requestWriteOnlyAccessToEvents()) ?? false
    }

    public func save(_ calendarEvent: ConcertCalendarEvent) throws {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = calendarEvent.title
        event.startDate = calendarEvent.startDate
        event.endDate = calendarEvent.endDate
        event.isAllDay = calendarEvent.isAllDay
        event.location = calendarEvent.location
        event.notes = calendarEvent.notes
        event.url = calendarEvent.url
        event.timeZone = calendarEvent.timeZone
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
    }
}
