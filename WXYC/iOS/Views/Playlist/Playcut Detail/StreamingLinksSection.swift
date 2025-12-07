//
//  StreamingLinksSection.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core
import WXUI
import Playlist
import Metadata

struct StreamingLinksSection: View {
    let metadata: PlaycutMetadata
    let isLoading: Bool
    var onServiceTapped: ((StreamingService) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add it to your library")
                .font(.headline.smallCaps())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StreamingButton(
                    service: .spotify,
                    url: metadata.spotifyURL,
                    isLoading: isLoading,
                    onTap: onServiceTapped
                )
                
                StreamingButton(
                    service: .appleMusic,
                    url: metadata.appleMusicURL,
                    isLoading: isLoading,
                    onTap: onServiceTapped
                )
                
                StreamingButton(
                    service: .youtubeMusic,
                    url: metadata.youtubeMusicURL,
                    isLoading: isLoading,
                    onTap: onServiceTapped
                )
                
                StreamingButton(
                    service: .bandcamp,
                    url: metadata.bandcampURL,
                    isLoading: isLoading,
                    onTap: onServiceTapped
                )
                
                StreamingButton(
                    service: .soundcloud,
                    url: metadata.soundcloudURL,
                    isLoading: isLoading,
                    onTap: onServiceTapped
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(0.1))
        )
    }
}
