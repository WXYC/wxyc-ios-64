//
//  SiriTipViewPreview.swift
//  WXUISampleApp
//
//  Preview for SiriTipView component.
//

import SwiftUI
import WXUI

struct SiriTipViewPreview: View {
    @State private var isVisible = true

    var body: some View {
        VStack {
            Spacer()

            if isVisible {
                SiriTipView(isVisible: $isVisible) {
                    print("Dismissed")
                }
                .padding()
            }

            Spacer()

            Button("Reset") {
                isVisible = true
            }
            .padding()
        }
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

#Preview {
    SiriTipViewPreview()
}
