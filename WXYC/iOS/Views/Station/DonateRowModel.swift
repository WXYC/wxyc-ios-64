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
import struct WXYCAPIModels.AppConfig

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
    /// `nil` resolves to `true` because on a *fetched* config it means the
    /// backend predates the field, and the compile-time fallback is a perfectly
    /// good destination. The dark-ship case is carried by
    /// ``AppConfiguration/defaults`` pinning `false` explicitly rather than by
    /// this expression — `defaults` is what `config()` returns on every failure
    /// path, so a `nil` there would show the row in exactly the release meant
    /// to hide it.
    var isVisible: Bool {
        config.donateEnabled ?? true
    }

    /// Where the row sends the listener, resolved down the ladder: the fetched
    /// `donateUrl`, then the bootstrap literal's, then the compile-time
    /// ``RadioStation/donateURL``. A rung only wins if it yields a URL that can
    /// actually be opened.
    var destination: URL {
        for candidate in [config.donateUrl, AppConfiguration.defaults.donateUrl] {
            if let url = Self.browsableURL(candidate) {
                return url
            }
        }
        return RadioStation.WXYC.donateURL
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
