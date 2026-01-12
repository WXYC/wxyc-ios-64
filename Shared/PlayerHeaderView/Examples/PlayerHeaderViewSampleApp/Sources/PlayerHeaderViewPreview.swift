//
//  PlayerHeaderViewPreview.swift
//  PlayerHeaderViewSampleApp
//

import SwiftUI
import PlayerHeaderView
import Playback
import WXUI

struct PlayerHeaderViewPreview: View {
    var body: some View {
        ZStack {
            Rectangle()
                .foregroundStyle(WXYCGradient())
            PlayerHeaderView(
                visualizer: VisualizerDataSource()
            )
            .padding()
        }
    }
}

#Preview {
    PlayerHeaderViewPreview()
}
