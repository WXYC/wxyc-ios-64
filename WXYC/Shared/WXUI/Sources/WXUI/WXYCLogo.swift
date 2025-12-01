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
        WXYCBackgroundMeshAnimation()
            .opacity(colorScheme == .light ? 0.25 : 0.40)
            .clipShape(WXYCLogoShape())
            .glassEffectRegularIfAvailable(in: WXYCLogoShape())
    }
}

