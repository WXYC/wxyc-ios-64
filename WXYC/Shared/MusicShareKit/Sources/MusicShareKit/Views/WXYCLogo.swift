//
//  WXYCLogo.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 11/25/25.
//

import SwiftUI

struct WXYCLogo: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        BackgroundMesh()
            .opacity(colorScheme == .light ? 0.25 : 0.40)
            .clipShape(WXYCLogoShape())
            .glassEffect(.regular, in: WXYCLogoShape())
    }
}
