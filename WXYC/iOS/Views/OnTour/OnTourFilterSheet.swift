//
//  OnTourFilterSheet.swift
//  WXYC
//
//  The On Tour tab's filter sheet: a date-window segmented control, a venue
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

/// The filter sheet presented from the On Tour tab's Filter button.
struct OnTourFilterSheet: View {
    @Bindable var model: OnTourModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                dateSection
                genreSection
                venueSection
                togglesSection
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        model.filter.reset()
                        fireApplied("reset")
                    }
                    .disabled(!model.filter.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) { showButton }
        }
    }

    // MARK: - Sections

    private var dateSection: some View {
        Section("When") {
            Picker("Date window", selection: facetBinding(\.filter.dateWindow, facet: "date")) {
                ForEach(ConcertFilterState.DateWindow.allCases, id: \.self) { window in
                    Text(window.title).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // The genre chips are derived entirely from the fetched window's genres
    // (`model.availableGenres`), so the section is absent whenever no show carries
    // a genre — before the backend emits `Concert.genres`, or for a window of
    // unresolved shows. The vocabulary is never a hardcoded taxonomy list.
    @ViewBuilder
    private var genreSection: some View {
        if !model.availableGenres.isEmpty {
            Section("Genre") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(model.availableGenres, id: \.self) { genre in
                        genreChip(genre)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func genreChip(_ genre: String) -> some View {
        let isSelected = model.filter.selectedGenres.contains(genre)
        return Button {
            toggleGenre(genre)
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark").font(.caption2).fontWeight(.bold)
                }
                Text(genre).font(.subheadline).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(genre)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
            Toggle("Free shows only", isOn: facetBinding(\.filter.freeOnly, facet: "free"))
            Toggle("All-ages shows only", isOn: facetBinding(\.filter.allAgesOnly, facet: "all_ages"))
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

    // MARK: - Facet bindings

    // Facets write through a custom binding (rather than `$model.filter.*` +
    // `.onChange`) so `OnTourFilterApplied` fires exactly once per user action
    // and never on a programmatic change — a Reset clears every facet in one
    // assignment without tripping four per-facet events. The no-op guard also
    // keeps a set-to-the-same-value (e.g. re-tapping the current segment) silent.

    private func facetBinding<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<OnTourModel, Value>,
        facet: String
    ) -> Binding<Value> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: { newValue in
                guard newValue != model[keyPath: keyPath] else { return }
                model[keyPath: keyPath] = newValue
                fireApplied(facet)
            }
        )
    }

    // MARK: - Mutations / analytics

    private func toggleVenue(_ id: Int) {
        if model.filter.selectedVenueIDs.contains(id) {
            model.filter.selectedVenueIDs.remove(id)
        } else {
            model.filter.selectedVenueIDs.insert(id)
        }
        fireApplied("venue")
    }

    private func toggleGenre(_ genre: String) {
        if model.filter.selectedGenres.contains(genre) {
            model.filter.selectedGenres.remove(genre)
        } else {
            model.filter.selectedGenres.insert(genre)
        }
        fireApplied("genre")
    }

    /// Records a filter action, and — since the sheet is the only surface that
    /// *tightens* the filter — also emits ``OnTourFilteredToZero`` when this
    /// action is what emptied a non-empty window. (The header pills only clear
    /// facets, so they can never reach zero.)
    private func fireApplied(_ facet: String) {
        StructuredPostHogAnalytics.shared.capture(
            OnTourFilterApplied(facet: facet, activeCount: model.filter.activeFacetCount)
        )
        if model.filter.isActive, !model.allConcerts.isEmpty, model.filtered.isEmpty {
            StructuredPostHogAnalytics.shared.capture(OnTourFilteredToZero())
        }
    }
}
