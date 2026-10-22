//
//  SpotlightRowView.swift
//  WXYC
//
//  The inline playlist card for a who's-on entry: its role line and the time it was logged.
//
//  Created by Jake Bromberg on 10/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI

struct SpotlightRowView: View {
    let entry: SpotlightEntry

    var body: some View {
        HStack {
            Text(entry.roleLine ?? "")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(entry.broadcastDate, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("playlist.spotlightRow")
    }
}
