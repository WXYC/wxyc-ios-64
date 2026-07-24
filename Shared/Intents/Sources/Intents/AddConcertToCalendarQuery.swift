//
//  AddConcertToCalendarQuery.swift
//  Intents
//
//  The testable core behind "Add Concert to Calendar" (OT-C7, #630): resolves
//  a `ConcertEntity`'s backend id to the full `Concert`, maps it to the
//  shipped `ConcertCalendarEvent` (#538), and saves it through the injected
//  `CalendarEventSaving` seam. Reuses the same value type `ConcertCalendarSheet`
//  feeds into `EKEventEditViewController` for the in-app "Add to Calendar"
//  sheet, but this path is headless (no UI to present outside the app), so it
//  saves the mapped event directly rather than opening that editor for
//  confirmation.
//
//  `ConcertEntity` (OT-F1) carries only the minimal Spotlight-identity shape
//  -- headliner, subtitle, image -- not the venue address/city/state, doors
//  time, or share URL `ConcertCalendarEvent` needs, so `resolveAndSave`
//  re-resolves the full `Concert` via a `ConcertsFetching` fetcher before
//  mapping.
//
//  Takes `fetcher`/`calendarStore` as explicit parameters rather than
//  `@Dependency` properties -- unlike `ConcertEntityQuery`'s reindex seams,
//  an `AppIntent`'s `@Dependency` properties trap when read outside the
//  actual AppIntents-runtime-driven perform flow ("Dependency values can
//  only be accessed inside of the intent perform flow"), so a unit test that
//  calls `perform()` directly can't exercise them. The app-target
//  `AddConcertToCalendarIntent` (`WXYC/iOS/Intents.swift`) resolves the real
//  fetcher via `AppIntentServices.concertsFetcher()` and passes it in here --
//  the same `fetcher:` seam shape `ToursNearMeQuery.resolve(fetcher:...)`
//  already uses for the same reason, and why that intent (like `ToursNearMe`)
//  lives in the app target rather than here.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import Foundation

public enum AddConcertToCalendarQuery {

    /// The result of a resolve-map-save attempt. Every failure case carries
    /// enough to build a clear, human-readable dialog without the caller
    /// re-deriving it -- `AddConcertToCalendarIntent.perform()` switches over
    /// this directly.
    public enum Outcome: Equatable {
        /// Saved successfully; carries the exact mapped event so the caller
        /// can report analytics (`isAllDay`) and the dialog (`title`)
        /// without re-mapping.
        case added(ConcertCalendarEvent)
        /// `fetcher.fetchConcert(id:)` couldn't resolve the concert (a 404 --
        /// a since-cancelled or unknown show, or a transient fetch failure).
        case concertUnavailable
        /// The listener declined (or previously declined) write-only
        /// calendar access.
        case accessDenied
        /// Access was granted but the save itself threw. Carries the mapped
        /// event's title for the failure dialog.
        case saveFailed(title: String)
    }

    /// Resolves `concertID` to a `Concert`, maps it to a `ConcertCalendarEvent`,
    /// requests calendar access, and saves it -- in that order, so a denied
    /// or unavailable concert never reaches `calendarStore.save(_:)`.
    public static func resolveAndSave(
        concertID: Int,
        fetcher: any ConcertsFetching,
        calendarStore: any CalendarEventSaving
    ) async -> Outcome {
        guard let concert = try? await fetcher.fetchConcert(id: concertID) else {
            return .concertUnavailable
        }

        let calendarEvent = ConcertCalendarEvent(concert)

        guard await calendarStore.requestAccess() else {
            return .accessDenied
        }

        do {
            try calendarStore.save(calendarEvent)
        } catch {
            return .saveFailed(title: calendarEvent.title)
        }

        return .added(calendarEvent)
    }
}
