//
//  WXYCLogoPreview.swift
//  WXUI
//
//  Preview for WXYC logo component.
//
//  Created by Jake Bromberg on 12/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import WXUI

struct WXYCLogoPreview: View {
    var body: some View {
        WXYCLogo()
            .background(WXYCGradient())
    }
}

#Preview {
    WXYCLogoPreview()
}
