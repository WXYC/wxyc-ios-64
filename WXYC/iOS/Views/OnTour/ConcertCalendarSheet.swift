//
//  ConcertCalendarSheet.swift
//  WXYC
//
//  The "Add to Calendar" affordance for an On Tour show (#538). Two pieces:
//
//  1. `ConcertCalendarEditSheet` — a `UIViewControllerRepresentable` over
//     `EKEventEditViewController`, prefilled from the pure `ConcertCalendarEvent`
//     value type (all the date/location/notes math lives there, in the Concerts
//     package). The user confirms or edits before it lands in their calendar.
//  2. `.addToCalendar(_:surface:)` — a modifier both On Tour surfaces (the detail
//     chrome button and the row context menu) drive through, so they share one
//     write-only-access request, one editor presentation, and one denied-access
//     alert. A call site sets the bound trigger to a concert to initiate.
//
//  Access is requested at the **write-only** level (`requestWriteOnlyAccessToEvents`):
//  the app only ever adds events, never reads the user's calendar, so it asks for
//  the narrower add-only permission.
//
//  Every step reports `ConcertCalendarFlow`: `requested` when the trigger is set,
//  then `denied`, `cancelled`, or `saved`. The old `ConcertCalendarAdded` fired
//  only on a save, so a flow abandoned at the permission alert and one that never
//  started looked identical — both simply absent. The events carry the band, like
//  the rest of the intent tier.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Concerts
import SwiftUI

#if os(iOS)
import EventKit
import EventKitUI
import UIKit

/// Presents the system event editor prefilled with a concert's calendar entry,
/// sharing only the fields ``ConcertCalendarEvent`` derives.
struct ConcertCalendarEditSheet: UIViewControllerRepresentable {
    let concert: Concert
    /// The originating affordance ("detail" or "row"), recorded on save.
    let surface: String

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(
            calendarEvent: ConcertCalendarEvent(concert),
            identity: concert.analyticsIdentity,
            surface: surface,
            dismiss: dismiss
        )
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = context.coordinator.makeEvent(in: store)
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    /// Bridges the UIKit editor's delegate callbacks back to SwiftUI: builds the
    /// `EKEvent`, records the save, and dismisses the sheet.
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let calendarEvent: ConcertCalendarEvent
        private let identity: ConcertIdentity
        private let surface: String
        private let dismiss: DismissAction

        init(
            calendarEvent: ConcertCalendarEvent,
            identity: ConcertIdentity,
            surface: String,
            dismiss: DismissAction
        ) {
            self.calendarEvent = calendarEvent
            self.identity = identity
            self.surface = surface
            self.dismiss = dismiss
        }

        /// Copies the value type's fields onto a fresh `EKEvent` in `store`.
        func makeEvent(in store: EKEventStore) -> EKEvent {
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
            return event
        }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            // `.deleted` can't arise for an event that was never saved, but it
            // is not a save either, so it reports as an abandonment rather than
            // being dropped on the floor.
            StructuredPostHogAnalytics.shared.capture(
                ConcertCalendarFlow(
                    concert: identity,
                    surface: surface,
                    outcome: action == .saved ? "saved" : "cancelled"
                )
            )
            dismiss()
        }
    }
}
#endif

extension View {
    /// Adds the "Add to Calendar" flow to a surface. Setting `trigger` to a concert
    /// requests write-only calendar access and, on grant, presents the event
    /// editor; on denial it surfaces a Settings alert. `surface` labels the
    /// analytics ("detail" or "row"). The trigger is consumed (reset to `nil`)
    /// once handled, so re-adding the same show fires again.
    func addToCalendar(_ trigger: Binding<Concert?>, surface: String) -> some View {
        #if os(iOS)
        modifier(AddToCalendarModifier(trigger: trigger, surface: surface))
        #else
        // macOS add-to-calendar is deferred; EKEventEditViewController is iOS-only.
        self
        #endif
    }
}

#if os(iOS)
/// Owns the add-to-calendar presentation state so both On Tour surfaces get the
/// access request, editor sheet, and denied-access alert from one modifier.
private struct AddToCalendarModifier: ViewModifier {
    @Binding var trigger: Concert?
    let surface: String

    @State private var editTarget: Concert?
    @State private var accessDenied = false
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .task(id: trigger) { await resolveTrigger() }
            .sheet(item: $editTarget) { concert in
                ConcertCalendarEditSheet(concert: concert, surface: surface)
                    .ignoresSafeArea()
            }
            .alert("Calendar Access Off", isPresented: $accessDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Turn on calendar access for WXYC in Settings to add shows to your calendar.")
            }
    }

    /// Requests write-only access on a fresh trigger, then either presents the
    /// editor or raises the denied-access alert, and consumes the trigger.
    private func resolveTrigger() async {
        guard let concert = trigger else { return }
        let identity = concert.analyticsIdentity
        // Fires whether or not permission is already granted: this is the tap
        // count every later outcome is a rate over, so it must not be
        // conditional on anything that happens after it.
        record(identity, outcome: "requested")
        let store = EKEventStore()
        let granted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        if granted {
            editTarget = concert
        } else {
            record(identity, outcome: "denied")
            accessDenied = true
        }
        trigger = nil
    }

    private func record(_ identity: ConcertIdentity, outcome: String) {
        StructuredPostHogAnalytics.shared.capture(
            ConcertCalendarFlow(concert: identity, surface: surface, outcome: outcome)
        )
    }
}
#endif
