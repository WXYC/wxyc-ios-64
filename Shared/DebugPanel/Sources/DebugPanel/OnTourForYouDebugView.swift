//
//  OnTourForYouDebugView.swift
//  DebugPanel
//
//  Debug controls for the On Tour "For You" shelf, presented by long-pressing the
//  "On Tour" title. Toggles the loved-tier seed, overrides the station-tier
//  cap, and resets the "Not interested" dismissals — the explicit replacement for
//  the old silent auto-seed.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

#if DEBUG
/// A sheet of debug switches for the For You recommendation shelf. The dismissed-
/// shows reset is injected as a closure (the `VisualizerDebugView` pattern) so this
/// package needs no dependency on the Concerts store that actually holds the set.
public struct OnTourForYouDebugView: View {
    @Bindable private var state = OnTourForYouSeedDebugState.shared
    @Environment(\.dismiss) private var dismiss

    /// Clears the persisted "Not interested" dismissals. Injected because the store
    /// lives in the Concerts package, which DebugPanel deliberately doesn't link.
    private let onResetDismissed: () -> Void

    public init(onResetDismissed: @escaping () -> Void) {
        self.onResetDismissed = onResetDismissed
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
            }
            .navigationTitle("For You Shelf")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif
