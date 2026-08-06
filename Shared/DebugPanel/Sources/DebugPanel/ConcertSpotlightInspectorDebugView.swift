//
//  ConcertSpotlightInspectorDebugView.swift
//  DebugPanel
//
//  OT-Q2 (#632): a DEBUG inspector for the `wxyc.concerts` Spotlight index,
//  alongside `OnTourForYouDebugView` / `OnTourShowsDebugState`. `CSSearchable
//  Index` has no public enumeration API, so this can't show what the OS
//  actually holds — it dumps the app's own donated-state view instead: each
//  currently-donated concert's id/title/priority/expirationDate. A "Force
//  reconcile / reindex now" control re-runs the real
//  `ConcertSpotlightDonationService.reconcile` pass on demand, so the
//  donation + eviction path can be exercised on-device ahead of OT-C8 (#654)
//  wiring it up as an automatic launch/refresh observer.
//
//  Holds primitives only (``Row``) — the app target computes the dump from
//  `AppServices.ConcertSpotlightDonationService.debugRows` and the real
//  `OnTourModel` window, and injects both as closures, so this package keeps
//  no dependency on `AppServices`/`Concerts` for this feature. Mirrors
//  `OnTourForYouSeedDebugState`'s "primitives only" rationale.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import WXUI

#if DEBUG
/// A DEBUG-only inspector for the `wxyc.concerts` Spotlight index: a dump of
/// the app's donated-state view plus a "force reconcile / reindex now"
/// control that re-runs the real donation path.
public struct ConcertSpotlightInspectorDebugView: View {
    /// One dumped row: a donated concert's id/title, the priority `reconcile`
    /// donated it at, and its `expirationDate`. Mirrors `AppServices
    /// .ConcertSpotlightDonationService.DebugRow` field-for-field but stays a
    /// distinct type declared here, in DebugPanel, so this view needs no
    /// `AppServices` import.
    public struct Row: Identifiable, Sendable, Equatable {
        public let id: Int
        public let title: String
        public let priority: Int
        public let expirationDate: Date

        public init(id: Int, title: String, priority: Int, expirationDate: Date) {
            self.id = id
            self.title = title
            self.priority = priority
            self.expirationDate = expirationDate
        }
    }

    @State private var rows: [Row] = []
    @State private var isReconciling = false
    @State private var hasLoadedOnce = false

    /// Recomputes the dump. Injected because the real derivation
    /// (`ConcertSpotlightDonationService.debugRows`) needs the current
    /// `OnTourModel` window, which lives in the app target.
    private let onLoadRows: () async -> [Row]

    /// Re-runs the real `ConcertSpotlightDonationService.reconcile` pass.
    /// Injected for the same reason as ``onLoadRows`` — the app target owns
    /// the window, liked artists, station cap, and dismissed-id inputs
    /// `reconcile` needs.
    private let onForceReconcile: () async -> Void

    public init(
        onLoadRows: @escaping () async -> [Row],
        onForceReconcile: @escaping () async -> Void
    ) {
        self.onLoadRows = onLoadRows
        self.onForceReconcile = onForceReconcile
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !hasLoadedOnce {
                        ProgressView()
                    } else if rows.isEmpty {
                        Text("No concerts currently donated to wxyc.concerts.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                Text("id \(row.id) · priority \(row.priority)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("expires \(row.expirationDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Donated concerts")
                } footer: {
                    Text("The app's own donated-state view — the persisted last-donated id set intersected with the current curated window — not a live query of the CSSearchableIndex (Spotlight exposes no public enumeration API).")
                }

                Section {
                    Button {
                        Task { await forceReconcile() }
                    } label: {
                        HStack {
                            Text("Force reconcile / reindex now")
                            if isReconciling {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isReconciling)
                } footer: {
                    Text("Re-runs ConcertSpotlightDonationService.reconcile against the current window — the same production entry point OT-C8 will call automatically.")
                }
            }
            .sheetChrome(title: "Concert Spotlight")
            .task { await loadRows() }
            .refreshable { await loadRows() }
        }
    }

    private func loadRows() async {
        rows = await onLoadRows()
        hasLoadedOnce = true
    }

    private func forceReconcile() async {
        isReconciling = true
        await onForceReconcile()
        await loadRows()
        isReconciling = false
    }
}
#endif
