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
    @Environment(\.openURL) private var openURL
    let title: String
    let icon: LinkButtonLabel.Icon
    let url: URL
    var onTap: ((String) -> Void)?

    var body: some View {
        Button {
            // Recorded only once the system accepts the URL, so a link that
            // couldn't open (an uninstalled app, a rejected scheme) isn't
            // counted as a tap that went somewhere.
            openURL(url) { accepted in
                if accepted { onTap?(title) }
            }
        } label: {
            LinkButtonLabel(
                icon: icon,
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
