//
//  SpecialtyCardView.swift
//  WXYC
//
//  The specialty program's card: its logo (or a text tile drawn from its short
//  name and accent color), its name, a subtitle, and the tagline while no song
//  or who's-on entry has landed.
//
//  Created by Jake Bromberg on 10/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Artwork
import Playlist
import SwiftUI
import UIKit
import Wallpaper
import WXUI

struct SpecialtyCardView: View {
    let card: SpecialtyCard

    private static let cornerRadius = SongRowMetrics.cornerRadius

    /// Seeded with the screen's width so the first layout already has a
    /// logo-sized slot; `onGeometryChange` replaces it with the measured width.
    @State private var cardWidth: CGFloat = UIScreen.main.bounds.width
    @State private var shadowYOffset: CGFloat = 0

    var body: some View {
        WallpaperCard(cornerRadius: Self.cornerRadius) {
            BackgroundLayer(cornerRadius: Self.cornerRadius)
        } content: {
            HStack(alignment: .top, spacing: 0) {
                RowArtworkSlot(rowWidth: cardWidth) {
                    RowArtworkFrame(shadowYOffset: shadowYOffset) {
                        SpecialtyArtworkView(
                            program: card.program,
                            size: SongRowMetrics.artworkSide(rowWidth: cardWidth)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.program.name)
                        .font(.headline)
                    if let subtitle = card.showName {
                        Text(subtitle)
                            .font(.subheadline)
                    }
                    Text(card.djHandle)
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    if let nowLine = card.nowLine {
                        Text(nowLine)
                            .font(.subheadline.weight(.semibold))
                    }
                    if card.showsTagline, let tagline = card.program.tagline {
                        Text(tagline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.white)
                .padding(.vertical, SongRowMetrics.artworkPadding)
                .padding(.trailing, SongRowMetrics.artworkPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardWidth = $0 }
        .modifier(ScrollShadowModifier(shadowYOffset: $shadowYOffset, top: SongRowMetrics.shadowOffsetAtTop, bottom: SongRowMetrics.shadowOffsetAtBottom))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("playlist.specialtyCard")
    }
}

#Preview {
    VStack {
        SpecialtyCardView(card: SpecialtyCard(
            program: SpecialtyShowRef(id: 3, slug: "hogwash", name: "Hogwash", shortName: "HW", tagline: "Weird and wonderful", accentColor: "#B3261E"),
            showName: "Hogwash Hour",
            djHandle: "DJ Monster",
            placement: .aboveSongList,
            showsTagline: true,
            showsNowPlayingHeader: false
        ))
    }
    .padding()
    .background(.black)
}
