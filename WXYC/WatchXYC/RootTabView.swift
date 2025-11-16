//
//  RootTabView.swift
//  WatchXYC Watch App
//
//  Created by Jake Bromberg on 2/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core

struct RootTabView: View {
    let radioPlayerController: RadioPlayerController
    
    var body: some View {
        TabView {
            PlayerPage(radioPlayerController: radioPlayerController)
                .tag(0)
            PlaylistPage()
                .tag(1)
            DialADJPage()
                .tag(2)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
    }
}

#Preview {
    RootTabView(radioPlayerController: RadioPlayerController.shared)
}
