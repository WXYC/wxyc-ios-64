//
//  PlayerHeaderViewPreview.swift
//  PlayerHeaderView
//
//  Preview host for PlayerHeaderView development.
//
//  Created by Jake Bromberg on 12/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
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
