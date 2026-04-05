//
//  StreamingButton.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import SwiftUI
import Metadata
import Playlist

struct StreamingButton: View {
    let service: StreamingService
    let url: URL?
    let isLoading: Bool
    var onTap: ((StreamingService) -> Void)?

    @State private var showingSafari = false

    private var icon: LinkButtonLabel.Icon {
        if service.hasCustomIcon {
            .custom(name: service.iconName, bundle: .playlist)
        } else {
            .system(name: service.systemIcon)
        }
    }

    var body: some View {
        Group {
            if let url = url {
                Button {
                    onTap?(service)
                    if service.opensInBrowser {
                        showingSafari = true
                    } else {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    linkLabel(backgroundFill: AnyShapeStyle(service.color))
                }
                .sheet(isPresented: $showingSafari) {
                    SafariView(url: url)
                }
            } else {
                linkLabel(backgroundFill: AnyShapeStyle(service.color.opacity(0.3)))
                    .opacity(isLoading ? 0.5 : 0.3)
            }
        }
    }

    private func linkLabel(backgroundFill: AnyShapeStyle) -> some View {
        LinkButtonLabel(
            icon: icon,
            title: service.name,
            font: .caption,
            foregroundShapeStyle: AnyShapeStyle(.white),
            backgroundFill: backgroundFill,
            alignment: .leading,
            spacing: 8
        )
    }
}
