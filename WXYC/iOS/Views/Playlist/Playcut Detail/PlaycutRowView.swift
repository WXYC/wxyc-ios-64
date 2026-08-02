//
//  PlaycutRowView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Analytics
import SwiftUI
import UIKit
import WXUI
import Concerts
import LikedSongs
import Playlist
import Artwork
import Wallpaper

// MARK: - Artwork View Components

/// Common styling for artwork views. Not `private`: `SongRowContent` reads
/// `cornerRadius` for its failed-load placeholder so the two rows share one
/// source of truth rather than a hardcoded copy.
struct ArtworkStyle {
    static let cornerRadius: CGFloat = 6.0
    static let roundedRectangle = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
}

/// Displays loaded artwork image
struct LoadedArtworkView: View {
    let artwork: UIImage

    var body: some View {
        Image(uiImage: artwork)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(ArtworkStyle.roundedRectangle)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// Loading placeholder for artwork
struct LoadingArtworkView: View {
    var body: some View {
        ArtworkStyle.roundedRectangle
            .fill(.white.opacity(0.12))
    }
}

struct PlaycutRowView: View {
    let playcut: Playcut
    /// The zoom-transition namespace shared with the detail cover, so this row is
    /// the source the `PlaycutDetailView` animates out of (mirrors `ConcertRow`).
    let namespace: Namespace.ID
    let onSelect: (UIImage?) -> Void

    /// Stable time offset for animated mesh gradient (randomized once at init).
    private let stableTimeOffset = TimeInterval((-10..<10).randomElement()!)

    @Environment(Singletonia.self) private var appState
    @Environment(\.wallpaperMeshGradientPalette) private var wallpaperPalette
    @Environment(\.upcomingShowResolver) private var upcomingShowResolver

    /// The upcoming show to render on this row, resolved synchronously from the
    /// playcut's embedded feed value (no network call). A DEBUG override may
    /// synthesize a mock; release reads the embed directly.
    private var upcomingShow: Concert? {
        upcomingShowResolver.upcomingShow(for: playcut)
    }

    /// Animated mesh gradient using wallpaper-derived palette when available.
    private var meshGradient: AnimatedMeshGradient {
        AnimatedMeshGradient(
            colors: wallpaperPalette,
            timeOffset: stableTimeOffset
        )
    }

    private var artworkState: ArtworkLoader.State {
        appState.artworkLoader.state(for: playcut)
    }

    private var loadedArtwork: UIImage? {
        if case .loaded(let image) = artworkState { image } else { nil }
    }

    // Ticket geometry, used only when the row carries an upcoming show. The
    // notch centers sit on the seam between the song row and the stub, so the
    // punch-outs read as one torn perforation shared by both panels.
    private let ticketCornerRadius: CGFloat = 12
    private let notchRadius: CGFloat = 6

    var body: some View {
        Group {
            if let upcomingShow {
                ticketRow(show: upcomingShow)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                songRowPanel
            }
        }
        // Source for the detail cover's zoom transition — the whole row (plain or
        // ticket) is what animates into `PlaycutDetailView`.
        .matchedTransitionSource(id: playcut.id, in: namespace)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .animation(.easeInOut(duration: 0.25), value: upcomingShow)
    }

    /// The plain playlist row: a wallpaper-blurred glass panel with artwork, song
    /// info, and the like heart. Used when there's no upcoming show to attach.
    /// Shares `SongRowPanel`'s glass chrome with the Liked tab row.
    private var songRowPanel: some View {
        SongRowPanel(onTap: { onSelect(loadedArtwork) }) { proxy in
            songRow(proxy: proxy)
        }
    }

    /// The row rendered as a single ticket: the song row and the on-tour stub
    /// share one wallpaper background and one perforated outline, so the
    /// semicircle notches at their seam punch cleanly through to the wallpaper —
    /// rather than each panel drawing half a notch against its own surface.
    private func ticketRow(show: Concert) -> some View {
        let shape = TicketRowShape(
            cornerRadius: ticketCornerRadius,
            stubHeight: OnTourRowBadge.preferredHeight,
            notchRadius: notchRadius
        )
        return ZStack {
            BackgroundLayer(cornerRadius: ticketCornerRadius)
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    songRow(proxy: proxy)
                }
                .aspectRatio(2.5, contentMode: .fill)

                OnTourRowBadge(show: show, colors: appState.themeConfiguration.effectiveTicketColors)
                    .frame(height: OnTourRowBadge.preferredHeight)
            }
        }
        .glassEffectClearIfAvailable(in: shape)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(loadedArtwork)
        }
        .clipShape(shape)
        .overlay { shape.stroke(.white.opacity(0.12), lineWidth: 1) }
        .frame(maxWidth: .infinity)
    }

    /// The song-row content — artwork, title/artist/time, like heart — shared by
    /// the plain row and the ticket, and (via `SongRowContent`) with the Liked
    /// tab. Needs the enclosing `GeometryReader`'s proxy for the artwork's size.
    private func songRow(proxy: GeometryProxy) -> some View {
        SongRowContent(
            song: playcut,
            artworkState: artworkState,
            meshGradient: { meshGradient },
            proxy: proxy
        ) {
            // The play time is this row's detail line.
            ClockView(timeCreated: playcut.timeCreated)
                .foregroundStyle(.white.opacity(0.7))
        } trailing: {
            // Like heart — replaces the info-circle in the trailing slot (study
            // verdict B, docs/plans/492-liked-songs.md): same 44pt target, same
            // .title3 scale. "Tap for more" rides on the row tap, which already
            // fires the identical onSelect.
            LikeHeartButton(
                isLiked: appState.likedSongsStore.isLiked(
                    artistName: playcut.artistName,
                    songTitle: playcut.songTitle
                ),
                action: toggleLike
            )
            .padding(.trailing, 4)
        }
    }

    /// Toggles the song like and records the toggle. The event carries no
    /// artist or song identity — only lifecycle strings and the post-toggle
    /// size bucket.
    private func toggleLike() {
        let liked = appState.likedSongsStore.toggle(playcut)
        StructuredPostHogAnalytics.shared.capture(SongLikeToggled(
            action: liked ? "like" : "unlike",
            surface: "row",
            totalBucket: appState.likedSongsStore.totalBucket
        ))
    }
}

// MARK: - Ticket shape

/// The playlist row's ticket outline: a rounded rectangle with a circular notch
/// cut into each side edge at the seam (`stubHeight` up from the bottom), so the
/// punch-outs read through to the wallpaper. Mirrors `BoxOfficeTicketView`'s
/// `TicketShape` at feed scale.
private struct TicketRowShape: Shape {
    let cornerRadius: CGFloat
    let stubHeight: CGFloat
    let notchRadius: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var shape = Path(roundedRect: rect, cornerRadius: cornerRadius)
        let seamY = rect.maxY - stubHeight
        let diameter = notchRadius * 2
        let left = Path(ellipseIn: CGRect(
            x: rect.minX - notchRadius, y: seamY - notchRadius,
            width: diameter, height: diameter
        ))
        let right = Path(ellipseIn: CGRect(
            x: rect.maxX - notchRadius, y: seamY - notchRadius,
            width: diameter, height: diameter
        ))
        return shape.subtracting(left).subtracting(right)
    }
}

extension View {
    nonisolated public func clipRounded() -> some View {
        clipShape(Self.rectShape)
    }

    static nonisolated var rectShape: some Shape {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            AnyShape(ConcentricRectangle.rect(corners: .concentric))
        } else {
            AnyShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

#Preview {
    @Previewable @Namespace var zoomNamespace
    PlaylistView(selectedPlaycut: .constant(nil), zoomNamespace: zoomNamespace)
        .environment(Singletonia.shared)
        .environment(\.playlistService, PlaylistService())
        .background(WXYCBackground())
}

#Preview {
    @Previewable @Namespace var zoomNamespace
    PlaycutRowView(
        playcut: Playcut(
            id: 1,
            hour: 1706544000000,
            chronOrderID: 1,
            timeCreated: 1706549400000, // 3:30 PM
            songTitle: "Belleville",
            labelName: nil,
            artistName: "Laurel Halo",
            releaseTitle: "Atlas"
        ),
        namespace: zoomNamespace,
        onSelect: { _ in }
    )
    .environment(Singletonia.shared)
    .background(WXYCBackground())
}

