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
    /// Reports the editor's terminal action — `"saved"` or `"cancelled"` — to
    /// the presenting modifier, which owns the flow's analytics. The sheet
    /// captures nothing itself: it cannot observe its own interactive
    /// dismissal, so the one place that sees every ending has to be the one
    /// place that records them.
    let onOutcome: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(
            calendarEvent: ConcertCalendarEvent(concert),
            onOutcome: onOutcome,
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
        private let onOutcome: (String) -> Void
        private let dismiss: DismissAction

        init(
            calendarEvent: ConcertCalendarEvent,
            onOutcome: @escaping (String) -> Void,
            dismiss: DismissAction
        ) {
            self.calendarEvent = calendarEvent
            self.onOutcome = onOutcome
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
            onOutcome(action == .saved ? "saved" : "cancelled")
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

    /// The editor's terminal action, set by its delegate before it dismisses.
    ///
    /// Swiping the sheet away never calls that delegate, so `nil` here at
    /// dismissal time *is* the interactive dismissal — the one path that would
    /// otherwise leave a `"requested"` with no terminal outcome, which is
    /// precisely the hole this event was redesigned to close.
    @State private var editorOutcome: String?

    /// The identity of the show whose editor is up. Held separately because
    /// `sheet(item:)` has already cleared `editTarget` by the time `onDismiss`
    /// runs.
    @State private var editorIdentity: ConcertIdentity?

    func body(content: Content) -> some View {
        content
            .task(id: trigger) { await resolveTrigger() }
            .sheet(item: $editTarget, onDismiss: recordEditorDismissal) { concert in
                ConcertCalendarEditSheet(concert: concert) { outcome in
                    editorOutcome = outcome
                }
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
        // Consumed first: `.task(id:)` is cancellable and the row it hangs off
        // lives in a LazyVStack, so a re-run with the trigger still set would
        // emit a second "requested" and re-request access for one user tap.
        trigger = nil

        let identity = concert.analyticsIdentity
        // Fires whether or not permission is already granted: this is the tap
        // count every later outcome is a rate over, so it must not be
        // conditional on anything that happens after it.
        record(identity, outcome: "requested")

        let store = EKEventStore()
        do {
            if try await store.requestWriteOnlyAccessToEvents() {
                editorIdentity = identity
                editTarget = concert
            } else {
                record(identity, outcome: "denied")
                accessDenied = true
            }
        } catch {
            // A *thrown* request is not a refusal — device restrictions or an
            // EventKit failure. Reporting it as "denied" would inflate the
            // refusal rate with cases no Settings change can fix.
            record(identity, outcome: "failed")
            accessDenied = true
        }
    }

    /// Records the editor's terminal outcome once the sheet is actually gone,
    /// treating a dismissal the delegate never reported as an abandonment.
    private func recordEditorDismissal() {
        guard let identity = editorIdentity else { return }
        record(identity, outcome: editorOutcome ?? "cancelled")
        editorIdentity = nil
        editorOutcome = nil
    }

    private func record(_ identity: ConcertIdentity, outcome: String) {
        StructuredPostHogAnalytics.shared.capture(
            ConcertCalendarFlow(concert: identity, surface: surface, outcome: outcome)
        )
    }
}
#endif
