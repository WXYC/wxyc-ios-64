//
//  ExternalLinkButton.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Playlist

struct ExternalLinkButton: View {
    let title: String
    let imageName: String
    let url: URL
    var onTap: ((String) -> Void)?

    var body: some View {
        Button {
            onTap?(title)
            UIApplication.shared.open(url)
        } label: {
            LinkButtonLabel(
                icon: .custom(name: imageName, bundle: .playlist),
                title: title,
                font: .subheadline,
                foregroundShapeStyle: AnyShapeStyle(.primary),
                backgroundFill: AnyShapeStyle(.primary.opacity(0.15)),
                alignment: .center,
                spacing: 12
            )
        }
    }
}
