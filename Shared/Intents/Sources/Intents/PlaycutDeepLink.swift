//
//  PlaycutDeepLink.swift
//  Intents
//
//  Symmetric encode/decode for the `wxyc://playcut/<id>` deep link that
//  OpenPlaycut emits and AppLifecycleModifier.handleURL consumes. Keeping
//  both sides in the Intents module guarantees the two paths never drift.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

public enum PlaycutDeepLink {
    /// The `wxyc://` scheme host that identifies a playcut deep link.
    public static let host = "playcut"

    /// Builds the URL that, when opened, foregrounds the app on the given playcut.
    public static func url(for playcutID: UInt64) -> URL? {
        var components = URLComponents()
        components.scheme = "wxyc"
        components.host = host
        components.path = "/\(playcutID)"
        return components.url
    }

    /// Parses a `wxyc://playcut/<id>` URL back into a `Playcut.id`.
    /// Returns `nil` for URLs that use a different scheme, host, or a
    /// non-numeric identifier segment.
    public static func playcutID(from url: URL) -> UInt64? {
        guard url.scheme == "wxyc", url.host == host else { return nil }
        let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UInt64(trimmed)
    }
}
