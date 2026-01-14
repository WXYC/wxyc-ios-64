//
//  OverlaySheetPreview.swift
//  WXUI
//
//  Preview for OverlaySheet component.
//
//  Created by Jake Bromberg on 01/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import WXUI

struct OverlaySheetPreview: View {
    @State private var showSheet = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.purple, .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Button("Show Sheet") {
                showSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .overlaySheet(isPresented: $showSheet) {
            VStack {
                Text("Custom Sheet Content")
                    .font(.title)
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    OverlaySheetPreview()
}
