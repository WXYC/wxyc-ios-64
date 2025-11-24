//
//  BackgroundLayer.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/15/25.
//

import SwiftUI

struct BackgroundLayer: View, Animatable {
    let cornerRadius: CGFloat

    internal init(
        cornerRadius: CGFloat = 12
    ) {
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.ultraThinMaterial)
    }
}
