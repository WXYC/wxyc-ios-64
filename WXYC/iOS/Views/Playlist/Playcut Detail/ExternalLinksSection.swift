//
//  ExternalLinksSection.swift
//  WXYC
//
//  External links section (Discogs, etc.).
//
//  Created by Jake Bromberg on 12/06/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Playlist
import Metadata
import WXUI

struct ExternalLinksSection: View {
    let metadata: PlaycutMetadata
    var onLinkTapped: ((String) -> Void)?
    
    var body: some View {
        DetailCard(title: "More Info") {
            HStack(spacing: 12) {
                if let discogsURL = metadata.discogsURL {
                    ExternalLinkButton(
                        title: "Discogs",
                        icon: .custom(name: "discogs", bundle: .playlist),
                        url: discogsURL,
                        onTap: onLinkTapped
                    )
                }

                if let wikipediaURL = metadata.wikipediaURL {
                    ExternalLinkButton(
                        title: "Wikipedia",
                        icon: .custom(name: "wikipedia", bundle: .playlist),
                        url: wikipediaURL,
                        onTap: onLinkTapped
                    )
                }
            }
        }
        .tint(.primary)
    }
}
