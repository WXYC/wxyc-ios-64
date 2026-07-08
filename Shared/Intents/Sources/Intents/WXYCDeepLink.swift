//
//  WXYCDeepLink.swift
//  Intents
//
//  Canonical parser for every `wxyc://…` URL the app recognises. Making this
//  an enum means routing is a switch — new entities in F5 (`ShowEntity`,
//  `ArtistEntity`, …) each add a `case`, and the URL handler cannot silently
//  fall back to playback for an unknown host. Comparisons are case-insensitive
//  per RFC 3986; paths must match the exact form the encoder emits.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

public enum WXYCDeepLink: Equatable, Sendable {
    /// `wxyc://play` — legacy Siri / quick-action shortcut for the live stream.
    case play
    /// `wxyc://playcut/<id>` — opens the app on a specific playcut.
    case playcut(PlaycutID)

    /// URL scheme every WXYC deep link uses.
    public static let scheme = "wxyc"

    /// Parses `url` into a recognised deep link, or returns `nil` for anything
    /// unrecognised — malformed ids, unknown hosts, extra path segments, wrong
    /// scheme. Callers get "known link vs. not" as a single decision.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        guard let host = url.host?.lowercased() else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "play":
            guard segments.isEmpty else { return nil }
            self = .play
        case "playcut":
            guard segments.count == 1,
                  let id = PlaycutID.entityIdentifier(for: segments[0])
            else { return nil }
            self = .playcut(id)
        default:
            return nil
        }
    }

    /// Renders this link as the URL an external caller (Siri, Spotlight, a
    /// shortcut) would open. Returns `nil` only if `URLComponents` can't
    /// assemble the pieces — never in practice for the fixed shapes here.
    public var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .play:
            components.host = "play"
        case .playcut(let id):
            components.host = "playcut"
            components.path = "/\(id.entityIdentifierString)"
        }
        return components.url
    }
}
