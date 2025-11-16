//
//  BreakpointRowView.swift
//  WXYC
//
//  SwiftUI view for Breakpoint playlist entries
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
