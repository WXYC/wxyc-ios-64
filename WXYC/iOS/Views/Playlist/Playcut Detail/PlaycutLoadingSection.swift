//
//  PlaycutLoadingSection.swift
//  WXYC
//
//  Loading placeholder for playcut detail.
//
//  Created by Jake Bromberg on 12/06/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import WXUI

struct PlaycutLoadingSection: View {
    var body: some View {
        // padded: false — this section sizes itself with a fixed height rather
        // than the standard interior padding, so the card doesn't grow past it.
        DetailCard(padded: false) {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Loading...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
        }
    }
}
