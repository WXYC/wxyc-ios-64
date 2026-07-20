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
import DebugPanel
import PartyHorn
import PlayerHeaderView
import Playlist
import SwiftUI
import UIKit
import Wallpaper
import WXUI

struct PlaycutSelection: Equatable {
    let playcut: Playcut
    let artwork: UIImage?

    static func == (lhs: PlaycutSelection, rhs: PlaycutSelection) -> Bool {
        lhs.playcut.id == rhs.playcut.id
    }
}

struct PlaylistView: View {
    @Binding var selectedPlaycut: PlaycutSelection?

    @State private var playlistEntries: [any PlaylistEntry] = []
    @State private var onAir: OnAir = .unknown
    @Environment(\.playlistService) private var playlistService
    @Environment(\.isThemePickerActive) private var isThemePickerActive
    @Environment(\.themeAppearance) private var appearance

    @State private var visualizer = VisualizerDataSource()
    @State private var showVisualizerDebug = false
    @State private var showOnAirDebug = false
    @State private var showingPartyHorn = false
    @State private var showingTicketCTA = false
    @State private var showingSiriTip = false
    @State private var showingThemeTip = false
    @State private var showingRequestLine = false

    @Environment(Singletonia.self) var appState

    var body: some View {
        @Bindable var appState = appState
        
        ZStack {
            Color.clear
            
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
                        onrequestLine: requestLine.invitesConversation ? { showingRequestLine = true } : nil
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
                        colors: appState.themeConfiguration.effectiveTicketColors
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
                    ForEach(Array(playlistEntries.enumerated()), id: \.element.id) { index, entry in
                        let playcutIndex = playcutIndex(for: index)

                        if playcutIndex == 0 {
                            PlaylistSectionHeader(text: "now playing")
                        } else if playcutIndex == 1 {
                            PlaylistSectionHeader(text: "recently played")
                        }

                        playlistRow(for: entry)
                            .padding(.vertical, 8)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    .animation(.spring(duration: 0.4, bounce: 0.2), value: playlistEntries.map(\.id))
                    
                    // Footer button
                    if !playlistEntries.isEmpty {
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
        }

        .fullScreenCover(isPresented: $showingPartyHorn) {
            PartyHornSwiftUIView()
                .onAppear {
                    StructuredPostHogAnalytics.shared.capture(PartyHornPresented())
                }
        }
        .sheet(isPresented: $showingRequestLine) {
            RequestLineSheet(requestLine: requestLine, source: "banner")
        }
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
            guard let playlistService else { return }
            for await playlist in playlistService.updates() {
                withAnimation {
                    self.onAir = playlist.onAir
                    self.playlistEntries = playlist.timelineEntries
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
        if OnAirDebugState.shared.forceOnAir {
            return OnAirDebugState.shared.forcedDJName
        }
        return onAir.bannerTitle
    }

    /// Booth presence derived from the same on-air source as the banner title,
    /// so the "say hi" chip and the Request Line sheet agree with what the banner
    /// asserts. The debug "Force On Air Banner" toggle substitutes a named DJ so
    /// the chip and sheet can be exercised without a live show.
    private var requestLine: RequestLine {
        if OnAirDebugState.shared.forceOnAir {
            return RequestLine(onAir: .dj(OnAirDebugState.shared.forcedDJName))
        }
        return RequestLine(onAir: onAir)
    }

    /// Live design parameters for the on-air banner, driven by the debug controls.
    /// In release builds these read their persisted defaults, reproducing the shipping look.
    private var onAirBannerTheme: OnAirBannerTheme {
        let debug = OnAirDebugState.shared
        return OnAirBannerTheme(
            indicatorColor: Color(HSL(
                hue: debug.indicatorHue,
                saturation: debug.indicatorSaturation,
                lightness: debug.indicatorLightness
            )),
            indicatorBlurRadius: CGFloat(debug.indicatorBlurRadius),
            handleVariation: SFProVariation(
                weight: debug.handleWeight,
                width: debug.handleWidth,
                opticalSize: debug.handleOpticalSize,
                grade: debug.handleGrade
            ),
            adaptiveWidth: debug.adaptiveWidth,
            handleWidthFloor: debug.handleWidthFloor,
            requestLineTintOpacity: debug.requestLineTintOpacity,
            onAirSpacing: CGFloat(debug.onAirSpacing),
            handleLineSpacing: CGFloat(debug.handleLineSpacing)
        )
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
    private func playlistRow(for entry: any PlaylistEntry) -> some View {
        switch entry {
        case let playcut as Playcut:
            PlaycutRowView(playcut: playcut) { artwork in
                selectedPlaycut = PlaycutSelection(playcut: playcut, artwork: artwork)
            }

        case let breakpoint as Breakpoint:
            TextRowView(text: breakpoint.formattedDate)

        case _ as Talkset:
            TextRowView(text: "Talkset")

        case let showMarker as ShowMarker:
            TextRowView(text: showMarkerText(for: showMarker))

        default:
            EmptyView()
        }
    }

    private func showMarkerText(for marker: ShowMarker) -> String {
        if let djName = marker.djName {
            marker.isStart ? "\(djName) signed on" : "\(djName) signed off"
        } else {
            marker.isStart ? "Signed on" : "Signed off"
        }
    }

    /// Returns the playcut index (0-based) if the entry at the given index is a Playcut, or nil otherwise.
    private func playcutIndex(for index: Int) -> Int? {
        guard playlistEntries[index] is Playcut else { return nil }
        return playlistEntries[..<index].filter { $0 is Playcut }.count
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
    PlaylistView(selectedPlaycut: .constant(nil))
        .environment(Singletonia.shared)
        .environment(\.playlistService, PlaylistService())
        .background(WXYCBackground())
}
