//
//  OpenInDJAppButton.swift
//  WXYC
//
//  "Open in WXYC DJ" tile on the playcut detail: opens the play's catalog album
//  in the DJ app (wxyc-dj-ios) via `wxycdj://album/<id>`, where the DJ's Add to
//  Bin finishes the job. Renders nothing unless the play is catalog-linked and
//  the DJ app is installed, so listeners never see it (#1151). The tile itself
//  is an ExternalLinkButton; the parent records the tap, as for the other links.
//
//  Created by Jake Bromberg on 10/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI
import WXUI

struct OpenInDJAppButton: View {
    @Environment(\.canOpenURL) private var canOpenURL
    let playcut: Playcut
    var onTap: (() -> Void)?

    var body: some View {
        if let url = openableURL {
            DetailCard {
                ExternalLinkButton(
                    title: "Open in WXYC DJ",
                    icon: .system(name: "arrow.up.forward.app"),
                    url: url,
                    onTap: { _ in onTap?() }
                )
            }
            .tint(.primary)
            .foregroundStyle(.white)
        }
    }

    /// The DJ-app link, or `nil` when the play isn't catalog-linked or the DJ
    /// app can't be opened (not installed, or Mac Catalyst; see
    /// ``CanOpenURLAction``). Checked as the body renders rather than in an
    /// `onAppear`: a hidden button has no view to hang one on, and a
    /// placeholder would still take a slot in the detail's spaced `VStack`.
    /// Liked-tab details qualify too: `LikedSongSnapshot.toPlaycut()` carries
    /// the album id the like was saved (or later healed) with.
    private var openableURL: URL? {
        Self.openableURL(albumId: playcut.albumId, canOpen: { canOpenURL($0) })
    }

    /// The button's visibility rule, separated from the environment so it can
    /// be tested: a positive catalog album id, and a DJ app that can be opened.
    static func openableURL(albumId: Int?, canOpen: (URL) -> Bool) -> URL? {
        guard let url = DJAppLink.albumURL(albumId: albumId), canOpen(url) else { return nil }
        return url
    }
}
