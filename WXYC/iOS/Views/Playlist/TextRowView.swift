//
//  BreakpointRowView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/15/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core

struct TextRowView: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 15, weight: .bold).smallCaps())
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                GeometryReader { proxy in
                    BackgroundLayer(cornerRadius: proxy.size.height / 2)
                }
            )
    }
}
