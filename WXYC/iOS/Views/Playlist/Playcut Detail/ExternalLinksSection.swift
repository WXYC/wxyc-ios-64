//
//  ExternalLinksSection.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Metadata

struct ExternalLinksSection: View {
    let metadata: PlaycutMetadata
    var onLinkTapped: ((String) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More Info")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                if let discogsURL = metadata.discogsURL {
                    ExternalLinkButton(
                        title: "Discogs",
                        imageName: "discogs",
                        url: discogsURL,
                        onTap: onLinkTapped
                    )
                }
                
                if let wikipediaURL = metadata.wikipediaURL {
                    ExternalLinkButton(
                        title: "Wikipedia",
                        imageName: "wikipedia",
                        url: wikipediaURL,
                        onTap: onLinkTapped
                    )
                }
            }
        }
        .tint(.primary)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(0.1))
        )
    }
}
