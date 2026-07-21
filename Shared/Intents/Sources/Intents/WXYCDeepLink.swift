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
    /// A shared On Tour show. The public link is `https://wxyc.org/shows/<id>`
    /// (see ``init(universalLink:)``); `wxyc://concert/<id>` is the internal
    /// scheme alias for app-owned surfaces (Spotlight, shortcuts). Both resolve
    /// to the same On Tour poster detail.
    case concert(Int)

    /// URL scheme every WXYC deep link uses.
    public static let scheme = "wxyc"

    /// Host of the universal-link registry: the WXYC apex, which serves the
    /// `applinks` AASA and the `/shows/*` share pages.
    public static let universalLinkHost = "wxyc.org"

    /// The path word the apex registers for shared shows — the tab's voice
    /// ("shows"), not the API's ("concerts"). Matches ``Concert/shareURL``.
    static let showsPathWord = "shows"

    /// Parses a `wxyc://…` scheme URL into a recognised deep link, or returns
    /// `nil` for anything unrecognised — malformed ids, unknown hosts, extra path
    /// segments, wrong scheme. Callers get "known link vs. not" as a single
    /// decision. Universal (`https://`) links go through ``init(universalLink:)``.
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
        case "concert":
            guard segments.count == 1,
                  let id = Self.concertID(from: segments[0])
            else { return nil }
            self = .concert(id)
        default:
            return nil
        }
    }

    /// Parses an `https://wxyc.org/shows/<id>[-slug]` universal link into a
    /// ``concert(_:)``, or `nil` for any other web URL. Only `https` on the apex
    /// host validates — that's the shape the AASA authorises. The trailing
    /// `-slug` is ignored (a leading-integer parse), so a human-readable share
    /// link and the bare id resolve identically. `wxyc://` scheme URLs go through
    /// ``init(url:)`` instead; this initializer rejects them.
    public init?(universalLink url: URL) {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == Self.universalLinkHost
        else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" }
        guard segments.count == 2,
              segments[0].lowercased() == Self.showsPathWord,
              let id = Self.concertID(from: segments[1])
        else { return nil }
        self = .concert(id)
    }

    /// Resolves any URL delivered through `onOpenURL` into a deep link, whether
    /// it is a `wxyc://` scheme URL (``init(url:)``) or an
    /// `https://wxyc.org/shows/<id>` universal link (``init(universalLink:)``).
    /// A Smart App Banner hands its `app-argument` to the app through
    /// `onOpenURL` rather than as an `NSUserActivity`, and that argument is a
    /// share URL; parsing the scheme first, then the universal link, lets both
    /// spellings route identically. Returns `nil` for anything neither
    /// initializer recognises. Universal links that arrive as a *tapped* web
    /// link come in as an `NSUserActivity` and use ``init(universalLink:)`` at
    /// that call site instead.
    public init?(routing url: URL) {
        if let link = WXYCDeepLink(url: url) {
            self = link
        } else if let link = WXYCDeepLink(universalLink: url) {
            self = link
        } else {
            return nil
        }
    }

    /// Parses a concert id from a path segment: the leading run of ASCII digits,
    /// so `"4821"` and `"4821-jessica-pratt"` both yield `4821`. Returns `nil`
    /// for an empty, sign-prefixed (`"-1"`, `"+42"`), or non-numeric segment, and
    /// for a segment whose id run is followed by anything but a `-slug`
    /// (`"4821abc"` is rejected, not truncated).
    private static func concertID(from segment: String) -> Int? {
        let head = segment.prefix { $0 != "-" }
        guard !head.isEmpty, head.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(head)
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
        case .concert(let id):
            components.host = "concert"
            components.path = "/\(id)"
        }
        return components.url
    }
}
