//
//  OnTourFilterPills.swift
//  WXYC
//
//  The applied-filter pills shown beneath the On Tour tab's header. Each pill
//  names an engaged facet and clears just that facet when tapped. Renders nothing
//  when no facet is active.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import SwiftUI

/// A horizontally-scrolling strip of "clear this facet" pills.
struct OnTourFilterPills: View {
    @Binding var filter: ConcertFilterState

    /// Called with a facet key ("date"/"venue"/"free"/"all_ages") after a pill
    /// clears it, so the caller can record analytics.
    var onClear: (String) -> Void = { _ in }

    var body: some View {
        if filter.isActive {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if filter.dateWindow != .all {
                        pill(filter.dateWindow.title, facet: "date") {
                            filter.dateWindow = .all
                        }
                    }
                    if !filter.selectedVenueIDs.isEmpty {
                        pill("Venues (\(filter.selectedVenueIDs.count))", facet: "venue") {
                            filter.selectedVenueIDs = []
                        }
                    }
                    if filter.freeOnly {
                        pill("Free", facet: "free") {
                            filter.freeOnly = false
                        }
                    }
                    if filter.allAgesOnly {
                        pill("All ages", facet: "all_ages") {
                            filter.allAgesOnly = false
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func pill(_ label: String, facet: String, clear: @escaping () -> Void) -> some View {
        Button {
            clear()
            onClear(facet)
        } label: {
            HStack(spacing: 5) {
                Text(label).font(.footnote).fontWeight(.semibold)
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.16)))
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear \(label) filter")
    }
}
