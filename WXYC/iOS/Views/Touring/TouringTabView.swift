//
//  TouringTabView.swift
//  WXYC
//
//  The Touring tab: a date-ordered list of curated Triangle-area shows with an
//  instant, client-side filter sheet. Fetches the whole curated window once into
//  a `TouringSoonModel` and filters it in memory — every facet applies with no
//  refetch. The model is view-owned single-screen state (see the concurrency note
//  on `TouringSoonModel`); it is not shared with widgets or other scenes.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Concerts
import MusicShareKit
import SwiftUI
import Wallpaper

/// The root view of the Touring tab.
struct TouringTabView: View {
    @State private var model: TouringSoonModel
    @State private var isFilterSheetPresented = false
    @State private var selectedConcert: Concert?
    /// Latches the once-per-launch "tab viewed" event and the initial load so a
    /// tab switch-away-and-back doesn't re-fire analytics or re-fetch.
    @State private var hasAppeared = false

    /// Creates the tab. The default model talks to the live `GET /concerts`
    /// endpoint with the anonymous-session token; previews and tests inject a
    /// model backed by a stub fetcher.
    init(model: TouringSoonModel? = nil) {
        _model = State(wrappedValue: model ?? TouringSoonModel(
            fetcher: ConcertsFetcher(tokenProvider: MusicShareKit.authService)
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .task {
            if !hasAppeared {
                hasAppeared = true
                StructuredPostHogAnalytics.shared.capture(TouringTabViewed())
            }
            // Load on first appearance and whenever a prior attempt didn't reach
            // `.loaded` (a failure to retry). A successful load — even one that
            // returned zero shows — stays put, so revisiting the tab neither
            // re-fetches nor flashes the spinner.
            if model.phase != .loaded {
                await model.load()
            }
        }
        .sheet(isPresented: $isFilterSheetPresented) {
            TouringFilterSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedConcert) { concert in
            ConcertDetailSheet(concert: concert)
        }
    }

    // MARK: - Header

    private var header: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On Tour").font(.largeTitle).bold()
                    if let countLine {
                        Text(countLine).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
                filterButton
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)

            TouringFilterPills(
                filter: $model.filter,
                onClear: recordFilterApplied
            )
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var filterButton: some View {
        Button {
            StructuredPostHogAnalytics.shared.capture(TouringFilterSheetOpened())
            isFilterSheetPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                Text("Filter")
                if model.filter.activeFacetCount > 0 {
                    Text("\(model.filter.activeFacetCount)")
                        .font(.caption2).bold().monospacedDigit()
                        .foregroundStyle(.black)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Circle().fill(.white))
                }
            }
            .font(.subheadline).fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(.white.opacity(0.16)))
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("touring.filterButton")
        .accessibilityLabel(
            model.filter.activeFacetCount > 0
                ? "Filter, \(model.filter.activeFacetCount) active"
                : "Filter"
        )
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            centeredState { ProgressView().tint(.white) }
        case .failed:
            errorState
        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if model.allConcerts.isEmpty {
            emptyState(
                systemImage: "calendar",
                title: "No shows on the calendar",
                message: "We list curated Triangle-area shows here. Check back soon."
            )
        } else {
            // One filter pass feeds both the emptiness check and the list, rather
            // than re-deriving `model.filtered` for each.
            let filtered = model.filtered
            if filtered.isEmpty {
                filteredToZeroState
            } else {
                concertList(filtered)
            }
        }
    }

    private func concertList(_ concerts: [Concert]) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(concerts) { concert in
                    ConcertRow(concert: concert) { selectedConcert = concert }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .refreshable { await model.load() }
    }

    private var filteredToZeroState: some View {
        centeredState {
            Image(systemName: "line.3.horizontal.decrease.circle").font(.largeTitle)
            Text("No shows match your filters").font(.headline)
            Text("Try widening your filters to see more shows.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
            Button("Clear filters") {
                model.filter.reset()
                recordFilterApplied("reset")
            }
            .buttonStyle(.bordered).tint(.white)
            .padding(.top, 4)
        }
    }

    private var errorState: some View {
        centeredState {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle)
            Text("Couldn't load shows").font(.headline)
            Text("Check your connection and try again.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
            Button("Try Again") { Task { await model.load() } }
                .buttonStyle(.bordered).tint(.white)
                .padding(.top, 4)
        }
    }

    private func emptyState(systemImage: String, title: String, message: String) -> some View {
        centeredState {
            Image(systemName: systemImage).font(.largeTitle)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func centeredState<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 12) { content() }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Derived state

    private var countLine: String? {
        guard model.phase == .loaded else { return nil }
        let total = model.allConcerts.count
        guard total > 0 else { return nil }
        if model.filter.isActive {
            return "\(model.filtered.count) of \(total) shows"
        }
        return total == 1 ? "1 show" : "\(total) shows"
    }

    private func recordFilterApplied(_ facet: String) {
        StructuredPostHogAnalytics.shared.capture(
            TouringFilterApplied(facet: facet, activeCount: model.filter.activeFacetCount)
        )
    }
}

// MARK: - Concert detail sheet

/// Presents the full Box Office ticket for a tapped concert. The ticket carries
/// its own outbound CTA (`ctaURL`), so this is both the "detail" and the path to
/// tickets. Placed on a warm gradient so the ticket's glass and amber read even
/// off the wallpaper.
private struct ConcertDetailSheet: View {
    let concert: Concert
    @Environment(\.dismiss) private var dismiss
    @Environment(Singletonia.self) private var appState

    var body: some View {
        NavigationStack {
            ScrollView {
                BoxOfficeTicketView(show: concert, colors: appState.themeConfiguration.effectiveTicketColors)
                    .padding()
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(
                    colors: [Color(red: 0.25, green: 0.28, blue: 0.55),
                             Color(red: 0.6, green: 0.24, blue: 0.44),
                             Color(red: 0.5, green: 0.22, blue: 0.28)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold).foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
    }
}

// MARK: - Previews

#if DEBUG
/// A canned fetcher so the preview renders a loaded list with no network.
private struct PreviewConcertsFetcher: ConcertsFetching {
    func fetchConcerts(curated: Bool, from: Date?, to: Date?, page: Int, limit: Int) async throws -> ConcertsResponse {
        ConcertsResponse(concerts: Concert.previewList, pagination: PaginationInfo(page: 1, limit: limit, total: nil, hasMore: false))
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [Color(red: 0.25, green: 0.28, blue: 0.55), Color(red: 0.6, green: 0.24, blue: 0.44)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        TouringTabView(model: TouringSoonModel(fetcher: PreviewConcertsFetcher()))
    }
}

private extension Concert {
    /// A small spread of WXYC-canonical touring artists across venues/cities for
    /// the preview list. `nonisolated` so the preview's (nonisolated) stub fetcher
    /// can read it — the app target is main-actor-isolated by default.
    nonisolated static var previewList: [Concert] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        func day(_ offset: Int) -> Date {
            let base = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)) ?? Date(timeIntervalSince1970: 1_785_898_800)
            return calendar.date(byAdding: .day, value: offset, to: base) ?? base
        }
        let cradle = Venue(id: 3, slug: "cats-cradle", name: "Cat's Cradle", city: "Carrboro", state: "NC", address: nil)
        let motorco = Venue(id: 7, slug: "motorco", name: "Motorco", city: "Durham", state: "NC", address: nil)
        let local506 = Venue(id: 1, slug: "local-506", name: "Local 506", city: "Chapel Hill", state: "NC", address: nil)
        return [
            Concert(id: 1, venue: cradle, startsOn: day(0), headliningArtistRaw: "Jessica Pratt",
                    supportingArtistsRaw: ["Julie Byrne"], ticketURL: URL(string: "https://example.com/a"),
                    priceMin: 22, priceMax: 25, ageRestriction: "All Ages", status: .onSale),
            Concert(id: 2, venue: motorco, startsOn: day(3), headliningArtistRaw: "Chuquimamani-Condori",
                    ticketURL: URL(string: "https://example.com/b"), priceMin: 0, ageRestriction: "18+", status: .free),
            Concert(id: 3, venue: local506, startsOn: day(6), headliningArtistRaw: "Juana Molina",
                    ticketURL: URL(string: "https://example.com/c"), priceMin: 18, ageRestriction: nil, status: .soldOut),
        ]
    }
}
#endif
