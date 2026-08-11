//
//  StreamingButton.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Core
import Foundation
import SwiftUI
import Metadata
import Playlist

struct StreamingButton: View {
    let service: MusicService
    let url: URL?
    let isLoading: Bool
    var onTap: ((MusicService) -> Void)?

    @State private var showingSafari = false

    /// `url`, gated on actually belonging to `service` — a `spotify_url` field
    /// holding a Deezer (or spoofed) host renders no button rather than a
    /// mislabeled one. Defense-in-depth against a mislabeled backend field;
    /// see `MusicService.matchesHost(of:)` and WXYC/wxyc-ios-64#563.
    private var gatedURL: URL? {
        guard let url, service.matchesHost(of: url) else { return nil }
        return url
    }

    private var icon: LinkButtonLabel.Icon {
        if service.hasCustomIcon {
            .custom(name: service.iconName, bundle: .playlist)
        } else {
            .system(name: service.systemIcon)
        }
    }

    var body: some View {
        Group {
            if let url = gatedURL {
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
            title: service.displayName,
            font: .caption,
            foregroundShapeStyle: AnyShapeStyle(.white),
            backgroundFill: backgroundFill,
            alignment: .leading,
            spacing: 8
        )
    }
}
