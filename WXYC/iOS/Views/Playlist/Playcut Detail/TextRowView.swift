//
//  TextRowView.swift
//  WXYC
//
//  Text row component for playlist display.
//
//  Created by Jake Bromberg on 11/15/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Wallpaper
import WXUI

struct TextRowView: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 15, weight: .bold).smallCaps())
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .pillBackground { radius in
                BackgroundLayer(cornerRadius: CGFloat(radius))
            }
    }
}
