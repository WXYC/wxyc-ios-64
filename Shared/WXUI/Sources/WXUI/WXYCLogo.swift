//
//  WXYCLogo.swift
//  WXUI
//
//  WXYC logo view component.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

public struct WXYCLogo: View {
    @Environment(\.colorScheme) var colorScheme
    
    public init() {}
    
    public var body: some View {
        AnimatedMeshGradient()
            .opacity(colorScheme == .light ? 0.25 : 0.40)
            .clipShape(WXYCLogoShape())
            .glassEffectClearTintedInteractiveIfAvailable(
                tint: Color(
                    hue: 248 / 360,
                    saturation: 100 / 100,
                    brightness: 100 / 100,
                    opacity: 0.25
                ),
                in: WXYCLogoShape()
            )
    }
}
