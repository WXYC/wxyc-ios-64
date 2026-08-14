//
//  DonateRowModel.swift
//  WXYC
//
//  Decides whether the Station tab's Donate row appears and where it sends the
//  listener, from the best-known app configuration.
//
//  Created by Jake Bromberg on 08/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppServices
import Core
import Foundation

/// Visibility and destination for the Station tab's Donate row.
///
/// A value type rather than an `@Observable` class on purpose: the observable
/// state is `Singletonia.appConfig`, and reading that from a SwiftUI `body` to
/// build one of these registers the dependency correctly. A second observable
/// object here would duplicate the same state under a second owner.
struct DonateRowModel {
    /// The best-known configuration: the fetched `/config` once it lands, and
    /// ``AppConfiguration/defaults`` before that — or permanently, if the fetch
    /// keeps failing.
    let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    /// Whether to show the row at all.
    ///
    /// `nil` resolves to `false`: on a *fetched* config it means the backend
    /// doesn't serve the field — the live state until Backend-Service PR#2115
    /// deploys, not a legacy edge case — and the row is a solicitation, so
    /// absence resolves dark. It renders only when the backend says `true`
    /// explicitly. ``AppConfiguration/defaults`` pins `false` too, so every
    /// failure path agrees with this default rather than depending on it.
    var isVisible: Bool {
        config.donateEnabled ?? false
    }

    /// Where the row sends the listener: the fetched `donateUrl` when it
    /// yields a URL that can actually be opened, else the compile-time
    /// ``RadioStation/donateURL``. (``AppConfiguration/defaults`` carries no
    /// `donateUrl`, so there is no middle rung.)
    var destination: URL {
        Self.browsableURL(config.donateUrl) ?? RadioStation.WXYC.donateURL
    }

    /// `SFSafariViewController` requires an http(s) URL and traps on anything
    /// else, so a rung carrying `""` — what Backend-Service serves for an unset
    /// `DONATE_URL`, following its `process.env.X || ''` shape — a
    /// scheme-relative string, or a `mailto:`/`javascript:` URL counts as
    /// absent rather than as a destination.
    private static func browsableURL(_ candidate: String?) -> URL? {
        guard let candidate,
              let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }
}
