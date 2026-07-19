//
//  OnTourTabView.swift
//  WXYC
//
//  The On Tour tab: a date-ordered list of curated Triangle-area shows with an
//  instant, client-side filter sheet. Fetches the whole curated window once into
//  a `OnTourModel` and filters it in memory — every facet applies with no
//  refetch. The model is view-owned single-screen state (see the concurrency note
//  on `OnTourModel`); it is not shared with widgets or other scenes.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Concerts
import LikedSongs
import MusicShareKit
import SwiftUI
import Wallpaper

#if DEBUG
import Logger  // For You shelf debug diagnostic + seed (see recommendations(for:))
#endif

/// The root view of the On Tour tab.
struct OnTourTabView: View {
    @Environment(Singletonia.self) private var appState
    @State private var model: OnTourModel
    @State private var isFilterSheetPresented = false
    @State private var selectedConcert: Concert?
    /// The zoom-transition namespace tying each row to the poster detail it opens.
    @Namespace private var zoomNamespace
    /// Latches the once-per-launch "tab viewed" event and the initial load so a
    /// tab switch-away-and-back doesn't re-fire analytics or re-fetch.
    @State private var hasAppeared = false
    /// Latches the once-per-launch For You shelf impression, so scrolling the rail
    /// off and back or switching tabs doesn't re-fire it.
    @State private var hasRecordedForYouImpression = false

    /// PostHog key for the similar-tier noise cap; local default 3 when absent.
    private static let similarCapFlagKey = "on_tour_for_you_similar_cap"

    /// Creates the tab. The default model talks to the live `GET /concerts`
    /// endpoint with the anonymous-session token; previews and tests inject a
    /// model backed by a stub fetcher.
    init(model: OnTourModel? = nil) {
        _model = State(wrappedValue: model ?? OnTourModel(
            fetcher: ConcertsFetcher(tokenProvider: MusicShareKit.authService)
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .accessibilityIdentifier("onTourView")
        .task {
            if !hasAppeared {
                hasAppeared = true
                StructuredPostHogAnalytics.shared.capture(OnTourTabViewed())
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
            OnTourFilterSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $selectedConcert) { concert in
            ConcertDetailView(concert: concert)
                .navigationTransition(.zoom(sourceID: concert.id, in: zoomNamespace))
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

            OnTourFilterPills(
                filter: $model.filter,
                onClear: recordFilterApplied
            )
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var filterButton: some View {
        Button {
            StructuredPostHogAnalytics.shared.capture(OnTourFilterSheetOpened())
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
        .accessibilityIdentifier("onTour.filterButton")
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
        // Recommendations are derived from the same filtered window the list
        // shows, so an active facet narrows the shelf too (the locked prototype
        // assumption). Empty when there are no likes or nothing intersects.
        let recommendations = recommendations(for: concerts)
        return ScrollView {
            VStack(spacing: 12) {
                if !recommendations.isEmpty {
                    // Pinned above the date list, bleeding edge-to-edge (the rail
                    // owns its own horizontal insets), and it deliberately
                    // duplicates shows that also appear below.
                    ForYouShelfView(recommendations: recommendations, onSelect: selectForYou)
                        .onAppear { recordForYouImpression(recommendations) }
                }
                LazyVStack(spacing: 10) {
                    ForEach(concerts) { concert in
                        ConcertRow(concert: concert, namespace: zoomNamespace) { selectedConcert = concert }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)
        }
        .refreshable { await model.load() }
    }

    // MARK: - For You shelf

    /// The listener's id-bearing liked artists, projected from the likes store.
    /// The store is newest-first, so the engine's first-id-wins de-duplication
    /// keeps the most recently-liked display name for a repeated artist id.
    private var likedArtists: [LikedArtist] {
        appState.likedSongsStore.songs.compactMap { song in
            song.artistId.map { LikedArtist(id: $0, name: song.artistName) }
        }
    }

    /// Builds the For You shelf over `concerts`, reading the remotely-tunable
    /// similar-tier cap through the feature-flag provider (local default 3).
    private func recommendations(for concerts: [Concert]) -> [ForYouRecommendation] {
        let liked = likedArtists

        // In DEBUG, fall back to a seeded like so the shelf UI is exercisable
        // before the backend enrichment (WXYC/Backend-Service#1700) populates
        // `similar_artists`. Release builds match on real likes only.
        #if DEBUG
        let matchArtists = debugSeededLikes(liked, concerts: concerts)
        #else
        let matchArtists = liked
        #endif

        let recs: [ForYouRecommendation]
        if matchArtists.isEmpty {
            recs = []
        } else {
            let cap = appState.featureFlagProvider.integerValue(forKey: Self.similarCapFlagKey, default: 3)
            recs = ForYouShelf.recommendations(concerts: concerts, likedArtists: matchArtists, similarCap: cap)
        }

        #if DEBUG
        logForYouGate(liked: liked, matched: matchArtists, concerts: concerts, cards: recs.count)
        #endif

        return recs
    }

    #if DEBUG
    /// Debug-only: when the listener has no real id-bearing likes, fake one from
    /// the first concert with a resolved headliner so the Loved-tier shelf renders
    /// even before the backend `similar_artists` enrichment lands
    /// (WXYC/Backend-Service#1700 / #1701 / #1702). Never compiled into release.
    private func debugSeededLikes(_ liked: [LikedArtist], concerts: [Concert]) -> [LikedArtist] {
        guard liked.isEmpty,
              let seed = concerts.first(where: { $0.headliningArtistId != nil }),
              let seedID = seed.headliningArtistId else { return liked }
        return [LikedArtist(id: seedID, name: seed.headlineName)]
    }

    /// Debug-only diagnostic: prints every gate the For You shelf depends on so a
    /// "no shelf" can be localized (id-less likes vs an empty concerts feed). Fires
    /// on each list render; DEBUG-only so it never reaches production Sentry.
    private func logForYouGate(liked: [LikedArtist], matched: [LikedArtist], concerts: [Concert], cards: Int) {
        let withHeadlinerId = concerts.filter { $0.headliningArtistId != nil }.count
        let withSimilar = concerts.filter { !($0.similarArtists ?? []).isEmpty }.count
        Log(.info, category: .ui, """
            ForYou gate: likedSongs=\(appState.likedSongsStore.songs.count) \
            idBearingLikes=\(liked.count) \(liked.map { "\($0.id):\($0.name)" }) \
            seeded=\(matched.count != liked.count) | concerts=\(concerts.count) \
            withHeadlinerId=\(withHeadlinerId) withSimilarArtists=\(withSimilar) -> cards=\(cards)
            """)
    }
    #endif

    private func selectForYou(_ recommendation: ForYouRecommendation) {
        StructuredPostHogAnalytics.shared.capture(
            ForYouCardTapped(tier: recommendation.tier.analyticsName)
        )
        selectedConcert = recommendation.concert
    }

    /// Records the shelf impression once per launch, carrying the tier counts at
    /// first render — counts only, never which artists surfaced the cards.
    private func recordForYouImpression(_ recommendations: [ForYouRecommendation]) {
        guard !hasRecordedForYouImpression, !recommendations.isEmpty else { return }
        hasRecordedForYouImpression = true
        let lovedCount = recommendations.filter { $0.tier == .loved }.count
        StructuredPostHogAnalytics.shared.capture(
            ForYouShelfImpression(lovedCount: lovedCount, similarCount: recommendations.count - lovedCount)
        )
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
            OnTourFilterApplied(facet: facet, activeCount: model.filter.activeFacetCount)
        )
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
        OnTourTabView(model: OnTourModel(fetcher: PreviewConcertsFetcher()))
    }
    .environment(Singletonia.shared)
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
                    eventURL: URL(string: "https://catscradle.com/event/jessica-pratt"),
                    priceMin: 22, priceMax: 25, ageRestriction: "All Ages", status: .onSale,
                    genres: ["Rock", "Folk World & Country"]),
            Concert(id: 2, venue: motorco, startsOn: day(3), headliningArtistRaw: "Chuquimamani-Condori",
                    ticketURL: URL(string: "https://example.com/b"), priceMin: 0, ageRestriction: "18+", status: .free,
                    genres: ["Electronic"]),
            Concert(id: 3, venue: local506, startsOn: day(6), headliningArtistRaw: "Juana Molina",
                    ticketURL: URL(string: "https://example.com/c"), priceMin: 18, ageRestriction: nil, status: .soldOut,
                    genres: ["Rock", "Electronic"]),
        ]
    }
}
#endif
