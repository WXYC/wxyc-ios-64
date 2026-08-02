//
//  PlaceholderArtworkPreview.swift
//  WXUI
//
//  Preview for placeholder artwork view.
//
//  Created by Jake Bromberg on 12/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import WXUI

struct PlaceholderArtworkPreview: View {
    var body: some View {
        PlaceholderArtworkView(
            cornerRadius: 12,
            meshGradient: AnimatedMeshGradient()
        )
        .background(WXYCBackground())
    }
}

#Preview {
    PlaceholderArtworkPreview()
}
