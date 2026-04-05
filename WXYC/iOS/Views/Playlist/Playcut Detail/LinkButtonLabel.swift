//
//  LinkButtonLabel.swift
//  WXYC
//
//  A reusable button label with an icon, title, and rounded rectangle background.
//  Used by StreamingButton and ExternalLinkButton to share their common layout
//  structure while allowing each to customize color, font, and icon source.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

struct LinkButtonLabel: View {
    let icon: Icon
    let title: String
    let font: Font
    let foregroundShapeStyle: AnyShapeStyle
    let backgroundFill: AnyShapeStyle
    let alignment: Alignment
    let spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            IconView(icon: icon)
                .frame(width: 20, height: 16)
            Text(title)
                .font(font)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .foregroundStyle(foregroundShapeStyle)
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundFill)
        )
    }
}

// MARK: - Icon

extension LinkButtonLabel {
    enum Icon {
        case custom(name: String, bundle: Bundle?)
        case system(name: String)
    }
}

// MARK: - Icon View

private struct IconView: View {
    let icon: LinkButtonLabel.Icon

    var body: some View {
        switch icon {
        case .custom(let name, let bundle):
            Image(name, bundle: bundle)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .system(let name):
            Image(systemName: name)
                .font(.body)
        }
    }
}
