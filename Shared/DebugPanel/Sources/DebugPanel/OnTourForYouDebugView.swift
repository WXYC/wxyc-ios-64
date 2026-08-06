//
//  OnTourForYouDebugView.swift
//  DebugPanel
//
//  Debug controls for the On Tour "For You" shelf, presented by long-pressing the
//  "On Tour" title. Toggles the loved-tier seed, overrides the station-tier
//  cap, and resets the "Not interested" dismissals — the explicit replacement for
//  the old silent auto-seed. Also links out to the OT-Q2 (#632) Concert Spotlight
//  inspector — a sibling debug view, reachable from this sheet rather than a
//  second long-press entry point.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import WXUI

#if DEBUG
/// A sheet of debug switches for the For You recommendation shelf. The dismissed-
/// shows reset is injected as a closure (the `VisualizerDebugView` pattern) so this
/// package needs no dependency on the Concerts store that actually holds the set.
public struct OnTourForYouDebugView: View {
    @Bindable private var state = OnTourForYouSeedDebugState.shared

    /// Clears the persisted "Not interested" dismissals. Injected because the store
    /// lives in the Concerts package, which DebugPanel deliberately doesn't link.
    private let onResetDismissed: () -> Void

    /// Recomputes the Concert Spotlight inspector's dump. Injected — see
    /// ``ConcertSpotlightInspectorDebugView``'s own doc comment for why.
    private let onLoadConcertSpotlightRows: () async -> [ConcertSpotlightInspectorDebugView.Row]

    /// Forces a real `ConcertSpotlightDonationService.reconcile` pass. Injected —
    /// see ``ConcertSpotlightInspectorDebugView``'s own doc comment for why.
    private let onForceConcertSpotlightReconcile: () async -> Void

    public init(
        onResetDismissed: @escaping () -> Void,
        onLoadConcertSpotlightRows: @escaping () async -> [ConcertSpotlightInspectorDebugView.Row],
        onForceConcertSpotlightReconcile: @escaping () async -> Void
    ) {
        self.onResetDismissed = onResetDismissed
        self.onLoadConcertSpotlightRows = onLoadConcertSpotlightRows
        self.onForceConcertSpotlightReconcile = onForceConcertSpotlightReconcile
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Seed loved card", isOn: $state.seedLovedEnabled)
                } footer: {
                    Text("Fakes a liked artist from the first upcoming show with a resolved headliner so the loved-tier \"In your likes\" card renders before the backend similar-artists enrichment lands. Opt-in — it replaces the old auto-seed that faked this card silently.")
                }

                Section {
                    Stepper("Station tier cap: \(state.stationCapOverride)", value: $state.stationCapOverride, in: 0...10)
                } footer: {
                    Text("Overrides the PostHog station-tier cap. 0 uses the remote flag; a positive value forces the station tier on so its \"WXYC recommends\" cards can be previewed.")
                }

                Section {
                    Button("Reset dismissed shows", role: .destructive, action: onResetDismissed)
                } footer: {
                    Text("Clears every \"Not interested\" dismissal so hidden shows return to the shelf.")
                }

                Section {
                    NavigationLink("Concert Spotlight Inspector") {
                        ConcertSpotlightInspectorDebugView(
                            onLoadRows: onLoadConcertSpotlightRows,
                            onForceReconcile: onForceConcertSpotlightReconcile
                        )
                    }
                } footer: {
                    Text("Dumps the app's donated view of wxyc.concerts (OT-Q2, #632) and can force a reconcile pass on demand.")
                }
            }
            .sheetChrome(title: "For You Shelf")
        }
    }
}
#endif
