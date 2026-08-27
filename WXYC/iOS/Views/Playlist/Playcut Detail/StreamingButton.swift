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
    @Environment(\.openURL) private var openURL
    let service: MusicService
    let url: URL?
    let isLoading: Bool
    var onTap: ((MusicService) -> Void)?

    #if os(iOS)
    @State private var showingSafari = false
    #endif

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
                    #if os(iOS)
                    if service.opensInBrowser {
                        showingSafari = true
                    } else {
                        openURL(url)
                    }
                    #else
                    openURL(url)
                    #endif
                } label: {
                    linkLabel(backgroundFill: AnyShapeStyle(service.color))
                }
                #if os(iOS)
                .sheet(isPresented: $showingSafari) {
                    SafariView(url: url)
                }
                #endif
            } else {
                // Two different meanings share this placeholder, and before
                // wxyc-ios-64#1018 they were separated by a 0.2 opacity step —
                // which is to say not separated at all. `isLoading` here means
                // "Backend is still enriching this row and a link may yet
                // appear"; its absence means "this service has no link for this
                // record". The redaction is what makes the first read as work
                // in progress rather than as an answer.
                linkLabel(backgroundFill: AnyShapeStyle(service.color.opacity(0.3)))
                    .opacity(0.3)
                    .redacted(reason: isLoading ? .placeholder : [])
                    .accessibilityLabel(
                        isLoading
                            ? "\(service.displayName), still loading"
                            : "\(service.displayName), unavailable"
                    )
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
