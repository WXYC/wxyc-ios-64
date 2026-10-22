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

import Playlist
import SwiftUI

struct SpecialtyCardView: View {
    let card: SpecialtyCard

    private static let artworkSize: CGFloat = 72

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: Self.artworkSize, height: Self.artworkSize)
                .clipShape(.rect(cornerRadius: 10))

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
                if card.showsTagline, let tagline = card.program.tagline {
                    Text(tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("playlist.specialtyCard")
    }

    /// The logo when it loads; the text tile while it loads, when it fails, and when there is none,
    /// so the card never shows a broken image.
    @ViewBuilder
    private var artwork: some View {
        if let url = card.program.artwork?.squareURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    tile
                }
            }
        } else {
            tile
        }
    }

    private var tile: some View {
        let rgb = card.program.accentRGB
        return ZStack {
            Rectangle().fill(rgb.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .gray)
            Text(card.program.tileText)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(4)
        }
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
