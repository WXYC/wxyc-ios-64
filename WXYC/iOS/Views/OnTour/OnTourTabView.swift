//
//  OnTourTabView.swift
//  WXYC
//
//  The On Tour tab: a date-ordered list of curated Triangle-area shows, split
//  into month-titled sections, with an instant, client-side filter sheet.
//  Fetches the whole curated window once into a `OnTourModel` and filters it in
//  memory — every facet applies with no refetch. The model is view-owned
//  single-screen state (see the concurrency note on `OnTourModel`); it is not
//  shared with widgets or other scenes.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Concerts
import DebugPanel
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
    /// Presents the DEBUG For You seed/reset sheet (long-press the title). Unused
    /// in release — the long-press that sets it compiles only in DEBUG.
    @State private var showForYouDebug = false
    /// Raised when a shared-show deep link (#537) resolves to a hard miss — the id
    /// is in neither the loaded window nor answerable by a by-id fetch — so the
    /// tab shows a quiet "couldn't find that show" notice instead of a blank cover.
    @State private var showMissedLinkNotice = false

    /// PostHog key for the similar-tier noise cap; local default 3 when absent.
    private static let similarCapFlagKey = "on_tour_for_you_similar_cap"

    /// PostHog key for the station-recommended tier size cap. Local default **0**
    /// (tier off) so wiring the surface is behavior-neutral — the cold-start
    /// station tier only lights up once this is raised via PostHog, gating the
    /// controlled rollout (WXYC/wxyc-ios-64#551).
    private static let stationCapFlagKey = "on_tour_for_you_station_cap"

    /// Creates the tab. The default model talks to the live `GET /concerts`
    /// endpoint with the anonymous-session token; previews and tests inject a
    /// model backed by a stub fetcher.
    init(model: OnTourModel? = nil) {
        _model = State(wrappedValue: model ?? OnTourModel(
            fetcher: ConcertsFetcher(tokenProvider: MusicShareKit.authService)
        ))
    }

    var body: some View {
        content
            .accessibilityIdentifier("onTourView")
            .task {
                if !hasAppeared {
                    hasAppeared = true
                    StructuredPostHogAnalytics.shared.capture(OnTourTabViewed())
                }
                // Load on first appearance and whenever a prior attempt didn't
                // reach `.loaded` (a failure to retry). A successful load — even
                // one that returned zero shows — stays put, so revisiting the tab
                // neither re-fetches nor flashes the spinner.
                if model.phase != .loaded {
                    await model.load()
                }
            }
            // A shared-show link arrived (#537). `RootTabView` has already flipped
            // to this tab (materializing the view); resolve the id here and present
            // the poster detail. Keyed on the pending link so a new share while the
            // tab is up re-runs, and consuming it (→ nil) settles without re-firing.
            .task(id: appState.pendingConcertLink) {
                await openPendingConcertLink()
            }
            .alert("Couldn't find that show", isPresented: $showMissedLinkNotice) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("This show may have passed or is no longer listed.")
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
            .forYouDebugSheet(isPresented: $showForYouDebug) {
                appState.dismissedConcertsStore.resetState()
            }
    }

    // MARK: - Header

    /// Wraps a non-scrolling state (loading, error, empty) under a static header,
    /// so the title still shows when there's no list to scroll it with.
    private func staticLayout(@ViewBuilder _ body: () -> some View) -> some View {
        VStack(spacing: 0) {
            header
            body()
        }
    }

    private var header: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                // Title and Filter share one single-line row, centered against each
                // other — the count line sits below so the pill lines up with the
                // large title rather than the two-line block's midpoint.
                HStack(alignment: .center) {
                    Text("On Tour").font(.largeTitle).bold()
                        // Hidden dev affordance: long-press the title to open the
                        // For You seed/reset controls. DEBUG-only; no-op in release.
                        .debugLongPress { showForYouDebug = true }
                    Spacer()
                    filterButton
                }
                if let countLine {
                    Text(countLine).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
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
            staticLayout { centeredState { ProgressView().tint(.white) } }
        case .failed:
            staticLayout { errorState }
        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if model.allConcerts.isEmpty {
            staticLayout {
                emptyState(
                    systemImage: "calendar",
                    title: "No shows on the calendar",
                    message: "We list curated Triangle-area shows here. Check back soon."
                )
            }
        } else {
            // One filter pass feeds both the emptiness check and the list, rather
            // than re-deriving `model.filtered` for each.
            let filtered = model.filtered
            if filtered.isEmpty {
                staticLayout { filteredToZeroState }
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
        // Group once per render rather than inline in the `ForEach`.
        let sections = ConcertMonthSection.sections(for: concerts)
        return ScrollView {
            VStack(spacing: 12) {
                // The heading is the first scrolling element, so it scrolls up and
                // away inline with the list rather than staying pinned above it.
                header
                if !recommendations.isEmpty {
                    // Pinned above the date list, bleeding edge-to-edge (the rail
                    // owns its own horizontal insets), and it deliberately
                    // duplicates shows that also appear below.
                    ForYouShelfView(recommendations: recommendations, onSelect: selectForYou, onDismiss: dismissForYou)
                        .onAppear { recordForYouImpression(recommendations) }
                }
                LazyVStack(alignment: .leading, spacing: 10) {
                    // Grouped into month sections (August 2026, September 2026, …).
                    // The window arrives `starts_on` ascending, so the sections and
                    // the rows within them stay chronological.
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.concerts) { concert in
                                ConcertRow(concert: concert, namespace: zoomNamespace) { selectedConcert = concert }
                            }
                        } header: {
                            monthSectionHeader(section.title)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)
        }
        .refreshable { await model.load() }
    }

    /// A month divider between runs of shows, e.g. "August 2026". Inline rather
    /// than pinned so it scrolls away with its section — matching the tab title,
    /// which is deliberately a scrolling element, not a pinned bar (and sidestepping
    /// a pinned header showing the wallpaper-tinted rows through it as they pass).
    private func monthSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3).fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Deep-link resolution (#537)

    /// Consumes a pending shared-show link: resolves the id through the window →
    /// by-id → miss ladder, then either presents the poster detail (an in-window
    /// hit zooms from its row; a by-id hit — a show outside the loaded window, or
    /// a past keepsake — presents directly) or raises a quiet "couldn't find that
    /// show" notice on a hard miss. `ConcertDetailView` decides the past-show
    /// treatment from the concert's date, so a passed show still opens as a
    /// keepsake. Fires `ConcertDeepLinkOpened` carrying only the link source and
    /// how it resolved — never the concert id — then clears the pending link so
    /// re-running this task (on consume → nil) is a no-op.
    private func openPendingConcertLink() async {
        guard let link = appState.pendingConcertLink else { return }
        let resolution = await model.resolveConcert(id: link.id)
        StructuredPostHogAnalytics.shared.capture(
            ConcertDeepLinkOpened(source: link.source, resolution: resolution.analyticsLabel)
        )
        if let concert = resolution.concert {
            selectedConcert = concert
        } else {
            showMissedLinkNotice = true
        }
        appState.consumePendingConcertLink()
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
    /// similar cap and station cap through the feature-flag provider (local
    /// defaults 3 / 0).
    private func recommendations(for concerts: [Concert]) -> [ForYouRecommendation] {
        let liked = likedArtists

        // In DEBUG, the explicit "Seed loved card" toggle (For You debug sheet)
        // can fabricate a like so the shelf UI is exercisable before the backend
        // enrichment (WXYC/Backend-Service#1700) populates `similar_artists`. This
        // replaces the old always-on auto-seed: nothing is fabricated unless the
        // tester opts in. Release builds always match on real likes only.
        #if DEBUG
        let seedState = OnTourForYouSeedDebugState.shared
        let matchArtists = (seedState.seedLovedEnabled || seedState.seedForcedForTesting)
            ? debugSeededLikes(liked, concerts: concerts)
            : liked
        #else
        let matchArtists = liked
        #endif

        // Always run the engine — even with zero likes. The station-recommended
        // tier reads `station_recommended` off the concerts, not the likes, so it
        // can fill the cold-start shelf on its own (#551, rewired on the boolean by
        // #577); there is no longer an empty-likes short-circuit. The station cap
        // defaults to 0 (tier off), so this stays behavior-neutral until PostHog
        // raises it.
        let similarCap = appState.featureFlagProvider.integerValue(forKey: Self.similarCapFlagKey, default: 3)
        // A positive debug station-cap override forces the tier on locally, ahead
        // of the PostHog flag; 0 (the default) defers to the flag.
        let flagStationCap = appState.featureFlagProvider.integerValue(forKey: Self.stationCapFlagKey, default: 0)
        #if DEBUG
        let stationCapOverride = seedState.stationCapOverride
        let stationCap = stationCapOverride > 0 ? stationCapOverride : flagStationCap
        #else
        let stationCap = flagStationCap
        #endif
        let recs = ForYouShelf.recommendations(
            concerts: concerts,
            likedArtists: matchArtists,
            similarCap: similarCap,
            stationCap: stationCap,
            dismissedConcertIDs: appState.dismissedConcertsStore.ids
        )

        #if DEBUG
        logForYouGate(liked: liked, matched: matchArtists, concerts: concerts, cards: recs)
        #endif

        return recs
    }

    #if DEBUG
    /// Debug-only: appends a synthetic liked artist — the first concert's resolved
    /// headliner — so a Loved-tier card renders even before the backend
    /// `similar_artists` enrichment lands (WXYC/Backend-Service#1700 / #1701 / #1702).
    /// Gated behind the explicit `OnTourForYouSeedDebugState.seedLovedEnabled`
    /// toggle (no longer always-on), so it never silently fabricates a card.
    /// Appends to `liked` rather than gating on `liked.isEmpty`, so the seed is
    /// deterministic even when real likes are present — which keeps the dismiss UI
    /// test's shelf reliable regardless of any likes persisted on the simulator.
    /// The engine de-dupes ids, so a seed that duplicates a real like is harmless.
    /// Never compiled into release.
    private func debugSeededLikes(_ liked: [LikedArtist], concerts: [Concert]) -> [LikedArtist] {
        guard let seed = concerts.first(where: { $0.headliningArtistId != nil }),
              let seedID = seed.headliningArtistId else { return liked }
        return liked + [LikedArtist(id: seedID, name: seed.headlineName)]
    }

    /// Debug-only diagnostic: prints every gate the For You shelf depends on so a
    /// "no shelf" can be localized (id-less likes vs an empty concerts feed). Fires
    /// on each list render; DEBUG-only so it never reaches production Sentry.
    private func logForYouGate(liked: [LikedArtist], matched: [LikedArtist], concerts: [Concert], cards: [ForYouRecommendation]) {
        let withHeadlinerId = concerts.filter { $0.headliningArtistId != nil }.count
        let withSimilar = concerts.filter { !($0.similarArtists ?? []).isEmpty }.count
        let recommended = concerts.filter(\.stationRecommended).count
        let counts = cards.tierCounts
        Log(.info, category: .ui, """
            ForYou gate: likedSongs=\(appState.likedSongsStore.songs.count) \
            idBearingLikes=\(liked.count) \(liked.map { "\($0.id):\($0.name)" }) \
            seeded=\(matched.count != liked.count) | concerts=\(concerts.count) \
            withHeadlinerId=\(withHeadlinerId) withSimilarArtists=\(withSimilar) \
            stationRecommended=\(recommended) -> cards=\(cards.count) \
            (loved=\(counts.loved) similar=\(counts.similar) station=\(counts.stationRecommended))
            """)
    }
    #endif

    private func selectForYou(_ recommendation: ForYouRecommendation) {
        StructuredPostHogAnalytics.shared.capture(
            ForYouCardTapped(tier: recommendation.tier.analyticsName)
        )
        selectedConcert = recommendation.concert
    }

    /// Handles "Not interested" on a For You card: records the tier-only analytics
    /// event, then dismisses the concert in the store. Reading the store's `ids` in
    /// `recommendations(for:)` means the shelf drops the card on the next render.
    private func dismissForYou(_ recommendation: ForYouRecommendation) {
        StructuredPostHogAnalytics.shared.capture(
            ForYouCardDismissed(tier: recommendation.tier.analyticsName)
        )
        appState.dismissedConcertsStore.dismiss(recommendation.concert.id)
    }

    /// Records the shelf impression once per launch, carrying the tier counts at
    /// first render — counts only, never which artists surfaced the cards.
    private func recordForYouImpression(_ recommendations: [ForYouRecommendation]) {
        guard !hasRecordedForYouImpression, !recommendations.isEmpty else { return }
        hasRecordedForYouImpression = true
        // Each tier is counted in its own bucket — station cards are never folded
        // into `similar` (#551).
        let counts = recommendations.tierCounts
        StructuredPostHogAnalytics.shared.capture(
            ForYouShelfImpression(
                lovedCount: counts.loved,
                similarCount: counts.similar,
                stationCount: counts.stationRecommended
            )
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
    private struct PreviewFetchError: Error {}

    func fetchConcerts(curated: Bool, from: Date?, to: Date?, page: Int, limit: Int) async throws -> ConcertsResponse {
        ConcertsResponse(concerts: Concert.previewList, pagination: PaginationInfo(page: 1, limit: limit, total: nil, hasMore: false))
    }

    /// Resolves the by-id rung against the same canned list; throws for an unknown
    /// id, mirroring the server's 404 so a preview can exercise a `.missed` link.
    func fetchConcert(id: Int) async throws -> Concert {
        guard let match = Concert.previewList.first(where: { $0.id == id }) else {
            throw PreviewFetchError()
        }
        return match
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
        // Spread across two calendar months so the preview exercises the month
        // section headers (two shows in August, then one in September).
        return [
            Concert(id: 1, venue: cradle, startsOn: day(0), headliningArtistRaw: "Jessica Pratt",
                    supportingArtistsRaw: ["Julie Byrne"], ticketURL: URL(string: "https://example.com/a"),
                    eventURL: URL(string: "https://catscradle.com/event/jessica-pratt"),
                    priceMin: 22, priceMax: 25, ageRestriction: "All Ages", status: .onSale,
                    genres: ["Rock", "Folk World & Country"]),
            Concert(id: 2, venue: motorco, startsOn: day(20), headliningArtistRaw: "Chuquimamani-Condori",
                    ticketURL: URL(string: "https://example.com/b"), priceMin: 0, ageRestriction: "18+", status: .free,
                    genres: ["Electronic"]),
            Concert(id: 3, venue: local506, startsOn: day(40), headliningArtistRaw: "Juana Molina",
                    ticketURL: URL(string: "https://example.com/c"), priceMin: 18, ageRestriction: nil, status: .soldOut,
                    genres: ["Rock", "Electronic"]),
        ]
    }
}
#endif

// MARK: - Debug affordance helpers

private extension View {
    /// Attaches a long-press action in DEBUG builds; a no-op passthrough in
    /// release. Keeps the hidden debug entry point off the release hit-testing path
    /// without an `onTapGesture` (disallowed) or a `#if` scattered at the call site.
    @ViewBuilder
    func debugLongPress(perform action: @escaping () -> Void) -> some View {
        #if DEBUG
        onLongPressGesture(perform: action)
        #else
        self
        #endif
    }

    /// Presents the For You debug sheet in DEBUG builds; a no-op passthrough in
    /// release, where `OnTourForYouDebugView` isn't compiled.
    @ViewBuilder
    func forYouDebugSheet(isPresented: Binding<Bool>, onResetDismissed: @escaping () -> Void) -> some View {
        #if DEBUG
        sheet(isPresented: isPresented) {
            OnTourForYouDebugView(onResetDismissed: onResetDismissed)
        }
        #else
        self
        #endif
    }
}
