//
//  ShowHeaderView.swift
//  WXYC
//
//  The header above a specialty show's rows in the scrollback: its artwork (logo or
//  text tile), program name, the airing's own name when it has one, and the DJ handle.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Artwork
import Playlist
import SwiftUI

struct ShowHeaderView: View {
    let header: ShowHeader

    private static let artworkSize: CGFloat = 48

    var body: some View {
        HStack(spacing: 12) {
            SpecialtyArtworkView(program: header.program, size: Self.artworkSize)
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(header.program.name)
                    .font(.headline)
                if let showName = header.showName {
                    Text(showName)
                        .font(.subheadline)
                }
                if let djHandle = header.djHandle {
                    Text(djHandle)
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("playlist.showHeader")
    }
}
