//
//  OpenInDJAppButton.swift
//  WXYC
//
//  "Open in WXYC DJ" tile on the playcut detail: opens the play's catalog album
//  in the DJ app (wxyc-dj-ios) via `wxycdj://album/<id>`, where the DJ's Add to
//  Bin finishes the job. Renders nothing unless the play is catalog-linked and
//  the DJ app is installed, so listeners never see it (#1151).
//
//  Created by Jake Bromberg on 10/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Playlist
import SwiftUI
import WXUI

struct OpenInDJAppButton: View {
    @Environment(\.openURL) private var openURL
    let playcut: Playcut

    var body: some View {
        if let url = openableURL {
            DetailCard {
                Button {
                    StructuredPostHogAnalytics.shared.capture(ExternalLinkTapped(
                        service: "WXYC DJ",
                        songTitle: playcut.songTitle,
                        artist: playcut.artistName,
                        album: playcut.releaseTitle ?? ""
                    ))
                    openURL(url)
                } label: {
                    LinkButtonLabel(
                        icon: .system(name: "arrow.up.forward.app"),
                        title: "Open in WXYC DJ",
                        font: .subheadline,
                        foregroundShapeStyle: AnyShapeStyle(.primary),
                        backgroundFill: AnyShapeStyle(.primary.opacity(0.15)),
                        alignment: .center,
                        spacing: 12
                    )
                }
            }
            .tint(.primary)
            .foregroundStyle(.white)
        }
    }

    /// The DJ-app link, or `nil` when the play isn't catalog-linked or the DJ
    /// app isn't installed. Checked as the body renders rather than in an
    /// `onAppear`: a hidden button has no view to hang one on, and a
    /// placeholder would still take a slot in the detail's spaced `VStack`.
    /// Liked-tab details never qualify — `LikedSongSnapshot.toPlaycut()` carries
    /// no `albumId`.
    private var openableURL: URL? {
        #if targetEnvironment(macCatalyst)
        // The DJ app is iPhone-only.
        return nil
        #else
        guard let url = DJAppLink.albumURL(for: playcut),
              UIApplication.shared.canOpenURL(url) else { return nil }
        return url
        #endif
    }
}
