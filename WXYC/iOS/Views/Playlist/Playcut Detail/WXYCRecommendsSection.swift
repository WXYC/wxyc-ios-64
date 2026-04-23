//
//  WXYCRecommendsSection.swift
//  WXYC
//
//  Displays up to 3 DJ-validated artist recommendations from the WXYC
//  semantic-index graph. Renders nothing when the artist is not in the
//  graph or the API is unavailable.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import SwiftUI
import SemanticIndex
import WXUI

struct WXYCRecommendsSection: View {
    let artistName: String

    @State private var neighbors: [SemanticIndexNeighbor] = []
    @State private var isLoading = true

    private let service = SemanticIndexService()

    var body: some View {
        if isLoading {
            loadingView
        } else if !neighbors.isEmpty {
            contentView
        }
    }

    private var loadingView: some View {
        ProgressView()
            .tint(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .task {
                let results = await service.recommendations(forArtistNamed: artistName)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.neighbors = results
                        self.isLoading = false
                    }
                }
            }
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WXYC Recommends")
                .font(.detailSectionHeader)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(neighbors) { neighbor in
                RecommendedArtistRow(neighbor: neighbor)
                    .simultaneousGesture(TapGesture().onEnded {
                        StructuredPostHogAnalytics.shared.capture(RecommendedArtistTapped(
                            sourceArtist: artistName,
                            recommendedArtist: neighbor.artist.canonicalName
                        ))
                    })

                if neighbor.id != neighbors.last?.id {
                    Divider()
                        .overlay(.white.opacity(0.2))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(0.1))
        )
    }
}
