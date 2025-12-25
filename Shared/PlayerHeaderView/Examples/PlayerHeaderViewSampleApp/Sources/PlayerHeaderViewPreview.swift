//
//  PlayerHeaderViewPreview.swift
//  PlayerHeaderViewSampleApp
//

import SwiftUI
import PlayerHeaderView
import Playback
import WXUI

struct PlayerHeaderViewPreview: View {
    @State var selectedPlayerType = PlayerControllerType.loadPersisted()

    var body: some View {
        ZStack {
            Rectangle()
                .foregroundStyle(WXYCGradient())
            PlayerHeaderView(
                visualizer: VisualizerDataSource(),
                selectedPlayerType: $selectedPlayerType
            )
            .padding()
        }
    }
}

#Preview {
    PlayerHeaderViewPreview()
}
