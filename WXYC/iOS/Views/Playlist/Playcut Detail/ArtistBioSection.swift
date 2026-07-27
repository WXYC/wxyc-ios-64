//
//  ArtistBioSection.swift
//  WXYC
//
//  Artist biography section in playcut detail.
//
//  Created by Jake Bromberg on 12/06/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Metadata
import MusicShareKit
import WXUI

struct ArtistBioSection: View {
    let bio: String
    let bioTokens: [ResolvedBioToken]?
    @Binding var expandedBio: Bool
    /// Whether to render the built-in "About the Artist" header. The flowsheet
    /// Playcut detail wants it inside the section (the default); the On Tour
    /// concert detail supplies its own header outside the card (matching the
    /// "WHERE" section), so it opts out.
    var showsHeader: Bool = true
    @State private var isTruncated: Bool = false
    @State private var parsedBio: AttributedString?

    // Authenticated, mirroring `PlaycutMetadataService(tokenProvider: MusicShareKit.authService)`
    // in PlaycutDetailView. `DiscogsAPIEntityResolver.shared` sends no
    // `Authorization` header, so `proxy/entity/resolve` 401s and every
    // ID-based artist reference in the bio (e.g. `[a87717]`) silently drops,
    // orphaning the surrounding punctuation.
    private let resolver: DiscogsEntityResolver = DiscogsAPIEntityResolver(tokenProvider: MusicShareKit.authService)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                Text("About the Artist")
                    .font(.detailSectionHeader)
                    .foregroundStyle(.primary)
            }

            parsedBioText
                .textSelection(.enabled)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(expandedBio ? nil : 4)
                .background(
                    TruncationDetector(text: parsedBioText, lineLimit: 4, isTruncated: $isTruncated)
                )

            if isTruncated {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedBio.toggle()
                    }
                } label: {
                    Text(expandedBio ? "Show Less" : "Read More")
                        .font(.caption.smallCaps())
                        .fontWeight(.bold)
                }
            }
        }
        .task {
            if let bioTokens {
                // Use pre-parsed tokens from the server (no network calls needed)
                parsedBio = DiscogsFormatter.applyLinkStyling(
                    to: ResolvedBioToken.render(bioTokens)
                )
            } else {
                // Fall back to client-side parsing with async entity resolution
                parsedBio = await DiscogsFormatter.parseToAttributedString(bio, resolver: resolver)
            }
        }
    }

    private var parsedBioText: Text {
        if let parsedBio {
            return Text(parsedBio)
        } else {
            // Show synchronously parsed version while async resolves
            return DiscogsFormatter.parse(bio)
        }
    }
}
