//
//  TruncationDetector.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

struct TruncationDetector: View {
    let text: Text
    let lineLimit: Int
    @Binding var isTruncated: Bool
    
    var body: some View {
        GeometryReader { geometry in
            text
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { fullTextGeometry in
                        Color.clear.onAppear {
                            checkTruncation(fullHeight: fullTextGeometry.size.height, availableWidth: geometry.size.width)
                        }
                        .onChange(of: fullTextGeometry.size) {
                            checkTruncation(fullHeight: fullTextGeometry.size.height, availableWidth: geometry.size.width)
                        }
                    }
                )
                .hidden()
        }
        .hidden()
    }
    
    private func checkTruncation(fullHeight: CGFloat, availableWidth: CGFloat) {
        // Estimate line height based on body font
        let estimatedLineHeight: CGFloat = 20
        let maxCollapsedHeight = CGFloat(lineLimit) * estimatedLineHeight * 1.2 // 1.2 for line spacing
        isTruncated = fullHeight > maxCollapsedHeight
    }
}
