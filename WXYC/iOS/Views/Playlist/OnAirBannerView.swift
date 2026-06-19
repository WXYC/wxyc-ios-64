//
//  OnAirBannerView.swift
//  WXYC
//
//  Persistent banner that promotes the current DJ's sign-on to the top of the playlist.
//
//  Created by Jake Bromberg on 06/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Wallpaper
import WXUI

/// A banner surfacing the DJ currently on the air at the top of the playlist.
///
/// Built on the shared ``TipCard`` chrome — the same cell type as the wallpaper-picker
/// tip — with a broadcast icon, a glowing green "ON AIR" caption, and the DJ's name
/// (e.g. "HOUNDSTOOTH"). Supplied by `ShowMarker.onAirTitle`.
struct OnAirBannerView: View {
    /// The DJ's name, e.g. "HOUNDSTOOTH", or the station name when none is available.
    let headline: String

    var body: some View {
        TipCard {
            BackgroundLayer(cornerRadius: 16)
        } content: {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        OnAirIndicator()

                        Text("ON AIR")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Text(headline)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }

                Spacer()
            }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("On air. \(headline)")
    }
}

/// A small green dot with a soft glow that gently pulses to evoke a live broadcast.
private struct OnAirIndicator: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 9, height: 9)
            .shadow(color: .green.opacity(0.9), radius: isPulsing ? 6 : 2)
            .opacity(isPulsing ? 1.0 : 0.65)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
            .accessibilityHidden(true)
    }
}

#Preview {
    OnAirBannerView(headline: "HOUNDSTOOTH")
        .padding()
        .background(.black)
}
