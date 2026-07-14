//
//  TouringFilterSheet.swift
//  WXYC
//
//  The Touring tab's filter sheet: a date-window segmented control, a venue
//  checklist grouped by region, Free / All-ages toggles, a Reset action, and a
//  live "Show N shows" call-to-action. The sheet edits the model's filter
//  directly, so the list behind it re-filters instantly as facets change — no
//  refetch, no "Apply" step.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Concerts
import SwiftUI

/// The filter sheet presented from the Touring tab's Filter button.
struct TouringFilterSheet: View {
    @Bindable var model: TouringSoonModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                dateSection
                venueSection
                togglesSection
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { model.filter.reset() }
                        .disabled(!model.filter.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) { showButton }
            .onChange(of: model.filter.dateWindow) { fireApplied("date") }
            .onChange(of: model.filter.selectedVenueIDs) { fireApplied("venue") }
            .onChange(of: model.filter.freeOnly) { fireApplied("free") }
            .onChange(of: model.filter.allAgesOnly) { fireApplied("all_ages") }
        }
    }

    // MARK: - Sections

    private var dateSection: some View {
        Section("When") {
            Picker("Date window", selection: $model.filter.dateWindow) {
                ForEach(ConcertFilterState.DateWindow.allCases, id: \.self) { window in
                    Text(Self.dateWindowTitle(window)).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var venueSection: some View {
        if model.venueGroups.isEmpty {
            Section("Venues") {
                Text("No venues in this window").foregroundStyle(.secondary)
            }
        } else {
            ForEach(model.venueGroups) { group in
                Section(group.region) {
                    ForEach(group.venues) { venue in
                        venueRow(venue)
                    }
                }
            }
        }
    }

    private func venueRow(_ venue: Venue) -> some View {
        let isSelected = model.filter.selectedVenueIDs.contains(venue.id)
        return Button {
            toggleVenue(venue.id)
        } label: {
            HStack {
                Text(venue.name).foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var togglesSection: some View {
        Section {
            Toggle("Free shows only", isOn: $model.filter.freeOnly)
            Toggle("All-ages shows only", isOn: $model.filter.allAgesOnly)
        } footer: {
            Text("All-ages hides only shows we can confirm are age-restricted.")
        }
    }

    // MARK: - Bottom CTA

    private var showButton: some View {
        Button { dismiss() } label: {
            Text(showButtonTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var showButtonTitle: String {
        let count = model.filtered.count
        return count == 1 ? "Show 1 show" : "Show \(count) shows"
    }

    // MARK: - Mutations / analytics

    private func toggleVenue(_ id: Int) {
        if model.filter.selectedVenueIDs.contains(id) {
            model.filter.selectedVenueIDs.remove(id)
        } else {
            model.filter.selectedVenueIDs.insert(id)
        }
    }

    private func fireApplied(_ facet: String) {
        StructuredPostHogAnalytics.shared.capture(
            TouringFilterApplied(facet: facet, activeCount: model.filter.activeFacetCount)
        )
    }

    // MARK: - Titles

    /// The short label for a date window, shared by the segmented control and the
    /// applied-filter pills.
    static func dateWindowTitle(_ window: ConcertFilterState.DateWindow) -> String {
        switch window {
        case .all: "All"
        case .tonight: "Tonight"
        case .thisWeekend: "Weekend"
        case .next7Days: "7 Days"
        }
    }
}
