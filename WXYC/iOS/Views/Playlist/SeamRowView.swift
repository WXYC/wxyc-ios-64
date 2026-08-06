//
//  SeamRowView.swift
//  WXYC
//
//  The playlist "seam" chip: a single centered pill marking where the DJ got on
//  the mic (a "mic break"), an hour boundary passed, or both — the rendered form
//  of a coalesced `Seam` from the Playlist package. Replaces the old "Talkset"
//  and bare-hour text rows.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI
import Wallpaper
import WXUI

struct SeamRowView: View {
    let seam: Seam

    var body: some View {
        chip
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(seam.plainLabel)
    }

    /// The hour to show, if the run crossed an hour boundary — the newest hour's
    /// dual-zone label (e.g. "3PM ET", or "12PM PT / 3PM ET" out of region).
    private var hourLabel: String? {
        seam.breakpoint?.formattedDate
    }

    private var chip: some View {
        HStack(spacing: 6) {
            if seam.hasMicBreak {
                Image(systemName: "microphone.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                Text("mic break".uppercased())
                    .font(.system(size: 14, weight: .bold).smallCaps())
                    .foregroundStyle(.white)
            }
            if seam.hasMicBreak, hourLabel != nil {
                Text("·")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            if let hourLabel {
                Text(hourLabel.uppercased())
                    .font(.system(size: 13, weight: .bold).smallCaps())
                    .foregroundStyle(.white)
            }
        }
        .fixedSize()
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .pillBackground { radius in
            BackgroundLayer(cornerRadius: CGFloat(radius))
        }
    }
}

#Preview {
    // A 3 PM ET hour boundary, built directly (the app target doesn't link the
    // PlaylistTesting stubs).
    let breakpoint = Breakpoint(
        id: 3,
        hour: 1_784_833_200_000,
        chronOrderID: 3,
        timeCreated: 1_784_833_200_000
    )
    return VStack(spacing: 16) {
        SeamRowView(seam: Seam(id: 1, hasMicBreak: true, breakpoint: nil))
        SeamRowView(seam: Seam(id: 2, hasMicBreak: false, breakpoint: breakpoint))
        SeamRowView(seam: Seam(id: 4, hasMicBreak: true, breakpoint: breakpoint))
    }
    .padding()
    .background(WXYCBackground())
}
