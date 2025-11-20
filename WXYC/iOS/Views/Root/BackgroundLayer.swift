//
//  BackgroundLayer.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/15/25.
//

import SwiftUI

struct BackgroundLayer: View, Animatable {
    let cornerRadius: CGFloat
    let colorScheme: ColorScheme?
    
    internal init(
        cornerRadius: CGFloat = 12,
        colorScheme: ColorScheme? = nil
    ) {
        self.cornerRadius = cornerRadius
        self.colorScheme = colorScheme
    }
    
    init() {
        self.cornerRadius = 12
        self.colorScheme = nil
    }
    
    var body: some View {
        if let colorScheme {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
                .preferredColorScheme(colorScheme)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
        }
    }
}
