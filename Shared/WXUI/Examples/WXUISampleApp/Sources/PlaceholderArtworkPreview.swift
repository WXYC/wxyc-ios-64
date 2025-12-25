//
//  PlaceholderArtworkPreview.swift
//  WXUISampleApp
//

import SwiftUI
import WXUI

struct PlaceholderArtworkPreview: View {
    var body: some View {
        PlaceholderArtworkView(
            cornerRadius: 12,
            shadowYOffset: 2,
            meshGradient: WXYCMeshAnimation().meshGradient
        )
        .background(WXYCBackground())
    }
}

#Preview {
    PlaceholderArtworkPreview()
}
