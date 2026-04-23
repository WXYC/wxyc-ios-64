//
//  ArtistStreamingLinksSection.swift
//  WXYC
//
//  Streaming links section for the artist detail view. Reuses the existing
//  LinkButtonLabel and StreamingButton patterns but adapts for artist-level
//  links from the semantic-index rather than track-level links from metadata.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Metadata
import SemanticIndex
import WXUI

struct ArtistStreamingLinksSection: View {
    let links: ArtistStreamingLinks
    var onServiceTapped: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Listen on")
                .font(.detailSectionHeader)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                if let url = links.appleMusicURL {
                    ArtistLinkButton(
                        service: .appleMusic,
                        url: url,
                        onTap: onServiceTapped
                    )
                }

                if let url = links.spotifyURL {
                    ArtistLinkButton(
                        service: .spotify,
                        url: url,
                        onTap: onServiceTapped
                    )
                }

                if let url = links.bandcampURL {
                    ArtistLinkButton(
                        service: .bandcamp,
                        url: url,
                        onTap: onServiceTapped
                    )
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

// MARK: - Artist Link Button

/// A streaming link button adapted for the artist detail context.
/// Reuses the existing `LinkButtonLabel` layout but always has a URL
/// (only shown when the link is available).
private struct ArtistLinkButton: View {
    let service: StreamingService
    let url: URL
    var onTap: ((String) -> Void)?

    @State private var showingSafari = false

    private var icon: LinkButtonLabel.Icon {
        if service.hasCustomIcon {
            .custom(name: service.iconName, bundle: .playlist)
        } else {
            .system(name: service.systemIcon)
        }
    }

    var body: some View {
        Button {
            onTap?(service.name)
            if service.opensInBrowser {
                showingSafari = true
            } else {
                UIApplication.shared.open(url)
            }
        } label: {
            LinkButtonLabel(
                icon: icon,
                title: service.name,
                font: .caption,
                foregroundShapeStyle: AnyShapeStyle(.white),
                backgroundFill: AnyShapeStyle(service.color),
                alignment: .leading,
                spacing: 8
            )
        }
        .sheet(isPresented: $showingSafari) {
            SafariView(url: url)
        }
    }
}
