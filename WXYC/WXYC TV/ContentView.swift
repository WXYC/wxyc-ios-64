//
//  ContentView.swift
//  WXYC TV
//
//  Created by Jake Bromberg on 3/1/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Image(ImageResource(name: "Background", bundle: .main))
                .resizable()
                .ignoresSafeArea()
            Color(white: 0, opacity: 0.5)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
            PlayerPage()
        }
    }
}

#Preview {
    ContentView()
}
