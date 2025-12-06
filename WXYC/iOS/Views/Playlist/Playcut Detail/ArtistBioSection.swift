//
//  ArtistBioSection.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core
import WXUI

struct ArtistBioSection: View {
    let bio: String
    @Binding var expandedBio: Bool
    @State private var isTruncated: Bool = false
    @State private var parsedBio: AttributedString?
    
    private let resolver: DiscogsEntityResolver = DiscogsAPIEntityResolver.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About the Artist")
                .font(.headline.smallCaps())
                .foregroundStyle(.primary)
            
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
            // Parse async with resolver to resolve artist IDs
            parsedBio = await DiscogsFormatter.parseToAttributedString(bio, resolver: resolver)
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
