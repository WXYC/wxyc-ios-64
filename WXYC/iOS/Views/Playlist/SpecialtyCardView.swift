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

struct SpecialtyCardView: View {
    let card: SpecialtyCard

    private static let artworkSize: CGFloat = 72

    var body: some View {
        HStack(spacing: 12) {
            SpecialtyArtworkView(program: card.program, size: Self.artworkSize)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
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
