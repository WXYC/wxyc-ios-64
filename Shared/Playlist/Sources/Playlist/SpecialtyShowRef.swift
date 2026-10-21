//
//  SpecialtyShowRef.swift
//  Playlist
//
//  The specialty program a DJ signed on as, from the flowsheet's `on_air.specialty`.
//
//  Created by Jake Bromberg on 10/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A specialty show (a named, recurring program) as referenced by `on_air.specialty`.
///
/// Decoded by hand-written `Codable` conformance rather than the generated type for the same
/// reason as ``FlowsheetResponse``: an unknown `default_spotlight_role` must not fail the decode,
/// so the role stays a plain string. Unknown keys are ignored.
public struct SpecialtyShowRef: Codable, Sendable, Hashable {
    public struct Artwork: Codable, Sendable, Hashable {
        public let squareURL: URL?

        public init(squareURL: URL?) {
            self.squareURL = squareURL
        }

        private enum CodingKeys: String, CodingKey {
            case squareURL = "square_url"
        }
    }

    public let id: Int
    public let slug: String
    public let name: String
    public let shortName: String?
    public let tagline: String?
    public let logsPlaycuts: Bool?
    /// The raw `default_spotlight_role` string; not an enum so an unrecognized future value survives.
    public let defaultSpotlightRole: String?
    public let artwork: Artwork?
    /// The show's accent color as a hex string (for example `#FF8800`).
    public let accentColor: String?

    public init(
        id: Int,
        slug: String,
        name: String,
        shortName: String? = nil,
        tagline: String? = nil,
        logsPlaycuts: Bool? = nil,
        defaultSpotlightRole: String? = nil,
        artwork: Artwork? = nil,
        accentColor: String? = nil
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.shortName = shortName
        self.tagline = tagline
        self.logsPlaycuts = logsPlaycuts
        self.defaultSpotlightRole = defaultSpotlightRole
        self.artwork = artwork
        self.accentColor = accentColor
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, name, tagline, artwork
        case shortName = "short_name"
        case logsPlaycuts = "logs_playcuts"
        case defaultSpotlightRole = "default_spotlight_role"
        case accentColor = "accent_color"
    }
}
