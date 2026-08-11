//
//  PlaylistView.swift
//  WXYC
//
//  Main playlist view displaying now playing and recent tracks with animated header,
//  visualizer, and support for tips, theme picker gesture, and easter egg access.
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Analytics
import AppIntents
import AppServices
import DebugPanel
import MusicShareKit
import PartyHorn
import PlayerHeaderView
import Playlist
import SwiftUI
import UIKit
import Wallpaper
import WXUI

/// The flowsheet row's selection state for the detail cover. Composes AppServices'
/// `NowPlayingItem` for its `{ playcut, artwork }` pair — see #408 — rather than
/// re-declaring those two fields, and adds only the zoom-transition identity on top.
struct PlaycutSelection: Equatable, Identifiable {
    private let item: NowPlayingItem
    /// The value the detail cover's zoom transition keys on. Defaults to the
    /// (unique) playcut id the flowsheet uses; the Liked tab overrides it with the
    /// snapshot's stable string key, because `LikedSongSnapshot.toPlaycut()`
    /// hardcodes id 0 — so every liked row would otherwise share source id 0 and
    /// the zoom couldn't tell which row it left from.
    let transitionID: AnyHashable

    var playcut: Playcut { item.playcut }
    var artwork: UIImage? { item.artwork }

    init(playcut: Playcut, artwork: UIImage?, transitionID: AnyHashable? = nil) {
        self.init(item: NowPlayingItem(playcut: playcut, artwork: artwork), transitionID: transitionID)
    }

    /// Bridges directly from AppServices' stream element (e.g. `NowPlayingService`'s
    /// `NowPlayingItem`), so the two types share one `{ playcut, artwork }` contract
    /// instead of each re-declaring it.
    init(item: NowPlayingItem, transitionID: AnyHashable? = nil) {
        self.item = item
        self.transitionID = transitionID ?? AnyHashable(item.playcut.id)
    }

    /// Identity is the zoom key — unique on both surfaces (the flowsheet's playcut
    /// id, the Liked tab's snapshot key), unlike `playcut.id`, which is 0 for every
    /// liked row. So `.fullScreenCover(item:)` treats distinct rows as distinct
    /// presentations and re-selecting the same row as the same one.
    var id: AnyHashable { transitionID }

    static func == (lhs: PlaycutSelection, rhs: PlaycutSelection) -> Bool {
        lhs.transitionID == rhs.transitionID
    }
}

struct PlaylistView: View {
    @Binding var selectedPlaycut: PlaycutSelection?
    /// The zoom-transition namespace shared with the detail cover, so each tapped
    /// playcut row is the source the `PlaycutDetailView` animates out of. Owned by
    /// `RootTabView`, where the `.fullScreenCover` lives.
    let zoomNamespace: Namespace.ID

    @State private var timelineItems: [TimelineItem] = []
    @State private var onAir: OnAir = .unknown
    @Environment(\.isThemePickerActive) private var isThemePickerActive
    @Environment(\.themeAppearance) private var appearance
    /// The banner's visual theme. Reads ``OnAirBannerTheme/default`` in Release;
    /// the composition root (`RootTabView`) overrides it with the live debug-panel
    /// value in `#if DEBUG || DEBUG_TESTFLIGHT` builds — this view never touches
    /// `OnAirDebugState` directly.
    @Environment(\.onAirBannerTheme) private var onAirBannerTheme

    @State private var visualizer = VisualizerDataSource()
    @State private var showVisualizerDebug = false
    @State private var showOnAirDebug = false
    @State private var showingPartyHorn = false
    @State private var showingTicketCTA = false
    @State private var showingSiriTip = false
    @State private var showingThemeTip = false
    @State private var showingRequestLine = false
    @State private var requestOutcome: RequestSentOutcome?

    /// Captured from `ScrollViewReader` on appearance, so the deep-link
    /// scroll (#434) can reach it from the `.task` modifiers below without
    /// re-nesting the whole body inside the reader's closure.
    @State private var scrollProxy: ScrollViewProxy?

    @Environment(Singletonia.self) var appState

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            Color.clear

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    // On air banner — the current DJ (or "Auto DJ"), pinned above the
                    // player. Hidden entirely when the on-air status is unknown (v1 or
                    // a backend that doesn't report it) so we never assert a false
                    // "Auto DJ" while a human DJ is live.
                    if let onAirBannerTitle {
                        OnAirBannerView(
                            headline: onAirBannerTitle,
                            theme: onAirBannerTheme,
                            onDebugTapped: onAirDebugTapped,
                            onRequestLine: requestLine.invitesConversation ? { showingRequestLine = true } : nil
                        )
                        .padding(.vertical, 8)
                    }

                    PlayerHeaderView(
                        visualizer: visualizer,
                        onDebugTapped: {
                            #if DEBUG || DEBUG_TESTFLIGHT
                            showVisualizerDebug = true
                            #endif
                        }
                    )
                    .lcdAccentColor(appearance.accentColor)
                    .lcdHSBOffsets(
                        min: appearance.lcdMinOffset,
                        max: appearance.lcdMaxOffset
                    )
                    .lcdActiveBrightness(appearance.lcdActiveBrightness)

                    // Ticket feature CTA — teaches the new Box Office ticket. The
                    // newest feature leads, so it sits above the other tips.
                    if showingTicketCTA {
                        TicketFeatureCTAView(
                            isVisible: $showingTicketCTA,
                            colors: appearance.ticketColors
                        ) {
                            appState.ticketFeatureCTAPersistence.recordDismissed()
                        }
                        .padding(.vertical, 8)
                    }

                    // Siri tip
                    if showingSiriTip {
                        SiriTipView(isVisible: $showingSiriTip) {
                            SiriTipView.recordDismissal()
                        }
                        .padding(.vertical, 8)
                    }

                    // Theme tip
                    if showingThemeTip {
                        ThemeTipView(isVisible: $showingThemeTip) {
                            appState.themePickerState.recordTipDismissedByUser()
                        }
                        .padding(.vertical, 8)
                    }

                    // Playlist entries
                    LazyVStack(spacing: 0) {
                        ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
                            let playcutIndex = playcutIndex(for: index)

                            if playcutIndex == 0 {
                                PlaylistSectionHeader(text: "now playing")
                            } else if playcutIndex == 1 {
                                PlaylistSectionHeader(text: "recently played")
                            }

                            playlistRow(for: item)
                                .padding(.vertical, 8)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                                // Stable scroll target for the #434 deep-link
                                // task below (`ScrollViewProxy.scrollTo`).
                                .id(item.id)
                        }
                        .animation(.spring(duration: 0.4, bounce: 0.2), value: timelineItems.map(\.id))
                    
                        // Footer button
                        if !timelineItems.isEmpty {
                            Button("what the freq?") {
                                showingPartyHorn = true
                            }
                            .foregroundStyle(.white)
                            .fontWeight(.black)
                            .foregroundStyle(AnimatedMeshGradient())
                            .padding(.top, 20)
                            .padding(.bottom, 20)
                            .safeAreaPadding(.bottom)
                        }
                    }
                }
                .padding(.top, isThemePickerActive ? 24 : 0)
                // Full-bleed scroll view: it clips at the screen edge, and the content
                // is inset via content margins rather than padding the ScrollView. That
                // gives every card the same width *and* a 12pt gutter its rim stroke and
                // drop shadow can draw into — the margin sits inside the clip, so nothing
                // gets shaved at the left/right edges.
                .contentMargins(.horizontal, 12, for: .scrollContent)
                .coordinateSpace(name: "scroll")
                // Captured into `scrollProxy` (#434) so the deep-link scroll
                // task below — which lives outside this closure's scope — can
                // drive it.
                .onAppear { scrollProxy = proxy }
            }
        }

        .fullScreenCover(isPresented: $showingPartyHorn) {
            PartyHornSwiftUIView()
                .onAppear {
                    StructuredPostHogAnalytics.shared.capture(PartyHornPresented())
                }
        }
        .sheet(isPresented: $showingRequestLine) {
            RequestLineSheet(requestLine: requestLine, source: "banner") {
                requestOutcome = .sent
            }
        }
        .requestSentHUD(outcome: $requestOutcome)
        #if DEBUG || DEBUG_TESTFLIGHT
        .sheet(isPresented: $showVisualizerDebug) {
            VisualizerDebugView(
                visualizer: visualizer,
                onResetThemePickerState: {
                    appState.themePickerState.persistence.resetState()
                },
                onResetSiriTip: {
                    SiriTipView.resetState()
                },
                onResetTicketCTA: {
                    appState.ticketFeatureCTAPersistence.resetState()
                }
            )
            .presentationDetents([.fraction(0.75)])
        }
        .sheet(isPresented: $showOnAirDebug) {
            OnAirBannerDebugView()
                .presentationDetents([.fraction(0.75)])
        }
        #endif
        .onAppear {
            // The ticket CTA leads (newest feature); the theme tip yields to it so
            // the two don't stack on a fresh install, where both would show.
            let showTicketCTA = appState.ticketFeatureCTAPersistence.shouldShow
            showingTicketCTA = showTicketCTA
            showingSiriTip = SiriTipView.recordLaunchAndShouldShow()
            showingThemeTip = !showTicketCTA && appState.themePickerState.persistence.shouldShowTip
        }
        .task {
            for await playlist in appState.playlistService.updates() {
                withAnimation {
                    self.onAir = playlist.onAir
                    self.timelineItems = playlist.timelineItems
                }
                // Publish the now-playing (first) playcut id for the debug
                // touring-shows mock to target. Harmless in release (unread).
                OnTourShowsDebugState.shared.firstPlaycutID =
                    playlist.timelineEntries.lazy.compactMap { ($0 as? Playcut)?.id }.first
                let playcuts = playlist.entries.compactMap { $0 as? Playcut }
                appState.artworkLoader.prune(keepingKeys: Set(playcuts.map(\.artworkCacheKey)))
                for playcut in playcuts {
                    appState.artworkLoader.load(playcut)
                }
                // A playcut deep link may have arrived before this refresh
                // populated `playlistEntries` (#434) — recheck on every tick
                // so a link that races the initial load still resolves once
                // its row shows up, rather than only on the one-shot
                // `.task(id:)` below.
                openPendingPlaycutIfPossible()
            }
        }
        // After the detail sheet dismisses, re-poll the loader for the dismissed
        // playcut. The detail view's metadata fallback may have written artwork
        // into the positive cache via cacheExternalArtwork; calling load() on a
        // .failed entry retries against the (now-populated) cache and succeeds.
        .onChange(of: selectedPlaycut) { oldValue, newValue in
            if let dismissed = oldValue, newValue == nil {
                appState.artworkLoader.load(dismissed.playcut)
            }
        }
        // A Spotlight/Siri tap or `wxyc://playcut/<id>` link arrived (#434).
        // `RootTabView` has already flipped to this tab (materializing the
        // view); resolve the row here. Keyed on the pending link so a new
        // deep link while this tab is up re-runs, and consuming it (→ nil)
        // settles without re-firing.
        .task(id: appState.pendingPlaycutLink) {
            openPendingPlaycutIfPossible()
        }
        .accessibilityIdentifier("playlistView")
    }

    /// The headline for the on-air banner, or `nil` when the banner should be hidden.
    ///
    /// Driven by the backend's tri-state `on_air` signal (``OnAir``): the DJ's name
    /// when a named DJ is live, "Auto DJ" when confirmed automation, and `nil`
    /// (banner hidden) when the status is unknown — so we never assert a false
    /// "Auto DJ" while a human DJ is on. The debug "Force On Air Banner" toggle
    /// substitutes a sample named DJ so the named layout can be previewed.
    private var onAirBannerTitle: String? {
        #if DEBUG || DEBUG_TESTFLIGHT
        if OnAirDebugState.shared.forceOnAir {
            return OnAirDebugState.shared.forcedDJName
        }
        #endif
        return onAir.bannerTitle
    }

    /// Booth presence derived from the same on-air source as the banner title,
    /// so the "say hi" chip and the Request Line sheet agree with what the banner
    /// asserts. The debug "Force On Air Banner" toggle substitutes a named DJ so
    /// the chip and sheet can be exercised without a live show.
    private var requestLine: RequestLine {
        #if DEBUG || DEBUG_TESTFLIGHT
        if OnAirDebugState.shared.forceOnAir {
            return RequestLine(onAir: .dj(OnAirDebugState.shared.forcedDJName))
        }
        #endif
        return RequestLine(onAir: onAir)
    }

    /// The debug-tap handler for the banner: presents the on-air controls sheet in debug
    /// builds, and is `nil` in release so the banner stays inert.
    private var onAirDebugTapped: (() -> Void)? {
        #if DEBUG || DEBUG_TESTFLIGHT
        return { showOnAirDebug = true }
        #else
        return nil
        #endif
    }

    @ViewBuilder
    private func playlistRow(for item: TimelineItem) -> some View {
        switch item {
        case .playcut(let playcut):
            PlaycutRowView(playcut: playcut, namespace: zoomNamespace) { artwork in
                selectedPlaycut = PlaycutSelection(playcut: playcut, artwork: artwork)
            }

        case .seam(let seam):
            SeamRowView(seam: seam)

        case .showMarker(let marker):
            TextRowView(text: showMarkerText(for: marker))
        }
    }

    private func showMarkerText(for marker: ShowMarker) -> String {
        if let djName = marker.djName {
            marker.isStart ? "\(djName) signed on" : "\(djName) signed off"
        } else {
            marker.isStart ? "Signed on" : "Signed off"
        }
    }

    /// Returns the playcut index (0-based) if the item at the given index is a
    /// playcut, or nil otherwise. Seams and show markers don't get a section
    /// header, so they're skipped in the count.
    private func playcutIndex(for index: Int) -> Int? {
        guard case .playcut = timelineItems[index] else { return nil }
        return timelineItems[..<index].filter { if case .playcut = $0 { true } else { false } }.count
    }

    /// The playcut entries currently on screen, for the deep-link router (#434),
    /// which matches on `Playcut` identity. Derived from `timelineItems` so it
    /// stays in sync with what's rendered.
    private var playcutEntries: [any PlaylistEntry] {
        timelineItems.compactMap { item -> Playcut? in
            if case .playcut(let playcut) = item { playcut } else { nil }
        }
    }

    /// Scrolls to the pending playcut deep link's row and consumes it (#434).
    /// A miss — the target isn't (yet) among ``playlistEntries`` — leaves the
    /// link pending, so a later refresh (see the retry call in the playlist
    /// `.task` above) or a fresh deep link can still resolve it; there's no
    /// "couldn't find that row" affordance for this ticket, matching
    /// ``PlaycutOpenRouter``.
    private func openPendingPlaycutIfPossible() {
        guard let link = appState.pendingPlaycutLink,
              let target = PlaycutOpenRouter.scrollTarget(for: link, in: playcutEntries),
              let scrollProxy
        else { return }
        // Defer the scroll one runloop hop so it runs *after* SwiftUI lays out
        // the LazyVStack rows for the `playlistEntries` we just matched (#434).
        // On a cold launch the deep link and the first playlist tick land in the
        // same main-actor frame — the row is in the data model (router HIT) but
        // not yet laid out — so a synchronous `scrollTo` no-ops against nothing,
        // yet we'd still consume the link and strand the user at the top of the
        // tab. Re-check the link inside the hop so a HIT scrolls-and-consumes
        // exactly once: a second call that races the hop, or a newer link that
        // superseded this one, finds it already gone and does nothing.
        Task { @MainActor in
            guard appState.pendingPlaycutLink == link else { return }
            withAnimation {
                scrollProxy.scrollTo(target, anchor: .center)
            }
            appState.consumePendingPlaycutLink()
        }
    }
}

struct PlaylistSectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .bold).smallCaps())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 16)
    }
}

#Preview {
    @Previewable @Namespace var zoomNamespace
    PlaylistView(selectedPlaycut: .constant(nil), zoomNamespace: zoomNamespace)
        .environment(Singletonia.shared)
        .background(WXYCGradient())
}
