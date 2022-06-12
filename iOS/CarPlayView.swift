//
//  CarPlayView.swift
//  WXYC
//
//  Created by Jake Bromberg on 6/12/22.
//  Copyright © 2022 WXYC. All rights reserved.
//

import SwiftUI
import Core

struct CarPlayView: View {
    @StateObject private var nowPlayingService = NowPlayingService.shared
//    var nowPlayingItem: NowPlayingItem? = nil
//    var nowPlayingObservation: Any? = nil

    var body: some View {
        VStack {
            if let nowPlayingItem = nowPlayingService.nowPlayingItem {
                Text(nowPlayingItem.playcut.artistName)
            } else {
                Text("Now playing")
            }
        }
        Text("Hello, World!")
    }
}

struct CarPlayView_Previews: PreviewProvider {
    static var previews: some View {
        CarPlayView()
    }
}
