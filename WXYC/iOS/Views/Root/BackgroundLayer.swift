//
//  BackgroundLayer.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/15/25.
//

import SwiftUI

struct BackgroundLayer<M: ShapeStyle>: View, Animatable {
    let cornerRadius: CGFloat
    let material: M

    init(cornerRadius: CGFloat = 12, material: M) {
        self.cornerRadius = cornerRadius
        self.material = material
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(material)
    }
}

extension BackgroundLayer where M == Material {
    init(cornerRadius: CGFloat = 12) {
        self.init(cornerRadius: cornerRadius, material: .ultraThinMaterial)
    }
}
