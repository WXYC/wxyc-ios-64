//
//  RecommendedArtistRow.swift
//  WXYC
//
//  A single row in the WXYC Recommends section, displaying a recommended
//  artist's name and genre as a NavigationLink.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import SemanticIndex

struct RecommendedArtistRow: View {
    let neighbor: SemanticIndexNeighbor

    private var destination: RecommendedArtist {
        RecommendedArtist(
            id: neighbor.artist.id,
            name: neighbor.artist.canonicalName,
            genre: neighbor.artist.genre
        )
    }

    var body: some View {
        NavigationLink(value: destination) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(neighbor.artist.canonicalName)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let genre = neighbor.artist.genre {
                        Text(genre)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let totalPlays = neighbor.artist.totalPlays {
                    Text(totalPlays, format: .number)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("plays")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
