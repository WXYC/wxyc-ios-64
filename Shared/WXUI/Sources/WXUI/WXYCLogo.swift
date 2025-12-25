//
//  WXYCLogo.swift
//  WXUI
//
//  Created by Jake Bromberg on 11/25/25.
//

import SwiftUI

public struct WXYCLogo: View {
    @Environment(\.colorScheme) var colorScheme
    
    public init() {}
    
    public var body: some View {
        WXYCMeshAnimation()
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
