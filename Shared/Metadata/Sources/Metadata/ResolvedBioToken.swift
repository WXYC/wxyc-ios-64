//
//  ResolvedBioToken.swift
//  Metadata
//
//  Server-provided Discogs markup tokens for rendering artist bios.
//  Decoded from the bioTokens field in the artist metadata API response.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import WXYCAPIModels

/// A pre-parsed markup token from the server's Discogs markup parser.
///
/// Mirrors `DiscogsMarkupParser.ResolvedToken` but decoded from JSON rather than
/// parsed client-side. When `bioTokens` is available in the API response, these
/// tokens can be rendered directly without running the local parser or making
/// entity resolution network calls.
public enum ResolvedBioToken: Sendable, Equatable, Codable {
    case plainText(String)
    case artistLink(name: String, displayName: String, url: URL)
    case labelName(String)
    case releaseLink(title: String, url: URL)
    case masterLink(title: String, url: URL)
    case bold(String)
    case italic(String)
    case underline(String)
    case urlLink(URL?, String)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case name
        case displayName = "display_name"
        case url
        case title
        case content
        case href
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "plainText":
            let text = try container.decode(String.self, forKey: .text)
            self = .plainText(text)

        case "artistLink":
            let name = try container.decode(String.self, forKey: .name)
            let displayName = try container.decode(String.self, forKey: .displayName)
            let url = try container.decode(URL.self, forKey: .url)
            self = .artistLink(name: name, displayName: displayName, url: url)

        case "labelName":
            let name = try container.decode(String.self, forKey: .name)
            self = .labelName(name)

        case "releaseLink":
            let title = try container.decode(String.self, forKey: .title)
            let url = try container.decode(URL.self, forKey: .url)
            self = .releaseLink(title: title, url: url)

        case "masterLink":
            let title = try container.decode(String.self, forKey: .title)
            let url = try container.decode(URL.self, forKey: .url)
            self = .masterLink(title: title, url: url)

        case "bold":
            let content = try container.decode(String.self, forKey: .content)
            self = .bold(content)

        case "italic":
            let content = try container.decode(String.self, forKey: .content)
            self = .italic(content)

        case "underline":
            let content = try container.decode(String.self, forKey: .content)
            self = .underline(content)

        case "urlLink":
            let href = try container.decodeIfPresent(URL.self, forKey: .href)
            let content = try container.decode(String.self, forKey: .content)
            self = .urlLink(href, content)

        default:
            // Unknown token types are decoded as empty plain text so they can be
            // filtered out by the caller without failing the entire decode.
            self = .plainText("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .plainText(let text):
            try container.encode("plainText", forKey: .type)
            try container.encode(text, forKey: .text)

        case .artistLink(let name, let displayName, let url):
            try container.encode("artistLink", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(displayName, forKey: .displayName)
            try container.encode(url, forKey: .url)

        case .labelName(let name):
            try container.encode("labelName", forKey: .type)
            try container.encode(name, forKey: .name)

        case .releaseLink(let title, let url):
            try container.encode("releaseLink", forKey: .type)
            try container.encode(title, forKey: .title)
            try container.encode(url, forKey: .url)

        case .masterLink(let title, let url):
            try container.encode("masterLink", forKey: .type)
            try container.encode(title, forKey: .title)
            try container.encode(url, forKey: .url)

        case .bold(let content):
            try container.encode("bold", forKey: .type)
            try container.encode(content, forKey: .content)

        case .italic(let content):
            try container.encode("italic", forKey: .type)
            try container.encode(content, forKey: .content)

        case .underline(let content):
            try container.encode("underline", forKey: .type)
            try container.encode(content, forKey: .content)

        case .urlLink(let href, let content):
            try container.encode("urlLink", forKey: .type)
            try container.encodeIfPresent(href, forKey: .href)
            try container.encode(content, forKey: .content)
        }
    }

    // MARK: - Generated Wire Type Mapping

    /// Maps the generated wire type (`WXYCAPIModels.DiscogsResolvedToken`, api.yaml's
    /// `DiscogsResolvedToken` schema) onto this domain type.
    ///
    /// This seam is deliberately tolerant rather than parity-strict with the wire shape:
    /// - An unknown `type` (the generator's `unknownDefaultOpenApi` catch-all case) returns
    ///   `nil`, so ``compactMap(_:)`` drops it from the mapped array.
    /// - A known `type` missing a required variant field, or carrying a URL string that fails
    ///   `URL(string:)`, degrades to ``plainText(_:)`` built from the best available text field
    ///   (`display_name` / `title` / `content` / `text` / `name`, in that priority order) instead
    ///   of failing. This initializer never throws: a malformed token loses its formatting, not
    ///   its words, and never takes the rest of the artist bio down with it (see WXYC/wxyc-ios-64#601).
    public init?(_ token: WXYCAPIModels.DiscogsResolvedToken) {
        switch token.type {
        case .unknownDefaultOpenApi:
            return nil

        case .plaintext:
            self = .plainText(token.text ?? Self.bestAvailableText(from: token))

        case .artistlink:
            if let name = token.name, let displayName = token.displayName, let url = token.url.flatMap(URL.init(string:)) {
                self = .artistLink(name: name, displayName: displayName, url: url)
            } else {
                self = .plainText(Self.bestAvailableText(from: token))
            }

        case .labelname:
            if let name = token.name {
                self = .labelName(name)
            } else {
                self = .plainText(Self.bestAvailableText(from: token))
            }

        case .releaselink:
            if let title = token.title, let url = token.url.flatMap(URL.init(string:)) {
                self = .releaseLink(title: title, url: url)
            } else {
                self = .plainText(Self.bestAvailableText(from: token))
            }

        case .masterlink:
            if let title = token.title, let url = token.url.flatMap(URL.init(string:)) {
                self = .masterLink(title: title, url: url)
            } else {
                self = .plainText(Self.bestAvailableText(from: token))
            }

        case .bold:
            if let content = token.content {
                self = .bold(content)
            } else {
                self = .plainText(Self.bestAvailableText(from: token))
            }

        case .italic:
            if let content = token.content {
                self = .italic(content)
            } else {
                self = .plainText(Self.bestAvailableText(from: token))
            }

        case .underline:
            if let content = token.content {
                self = .underline(content)
            } else {
                self = .plainText(Self.bestAvailableText(from: token))
            }

        case .urllink:
            guard let content = token.content else {
                self = .plainText(Self.bestAvailableText(from: token))
                return
            }
            guard let hrefString = token.href else {
                self = .urlLink(nil, content)
                return
            }
            guard let href = URL(string: hrefString) else {
                self = .plainText(Self.bestAvailableText(from: token))
                return
            }
            self = .urlLink(href, content)
        }
    }

    /// The best available text field on a generated token, in priority order, for degrading a
    /// malformed known-type token to ``plainText(_:)``. Falls back to the empty string when the
    /// token carries no text at all (mirroring the empty-`plainText` placeholder this type has
    /// always used for unrecognized shapes).
    private static func bestAvailableText(from token: WXYCAPIModels.DiscogsResolvedToken) -> String {
        token.displayName ?? token.title ?? token.content ?? token.text ?? token.name ?? ""
    }

    // MARK: - Rendering

    /// Renders an array of server-provided tokens to AttributedString.
    ///
    /// Uses the same rendering logic as `DiscogsMarkupParser.render(_:)` so the
    /// visual output is identical whether tokens come from the server or the
    /// local parser.
    public static func render(_ tokens: [ResolvedBioToken]) -> AttributedString {
        tokens.reduce(into: AttributedString()) { result, token in
            result.append(token.attributedString)
        }
    }

    /// Converts this token to an AttributedString with appropriate formatting.
    private var attributedString: AttributedString {
        switch self {
        case .plainText(let text):
            return AttributedString(text)

        case .artistLink(_, let displayName, let url):
            var attr = AttributedString(displayName)
            attr.link = url
            attr.underlineStyle = .single
            return attr

        case .labelName(let name):
            return AttributedString(name)

        case .releaseLink(let title, let url):
            var attr = AttributedString(title)
            attr.link = url
            attr.underlineStyle = .single
            return attr

        case .masterLink(let title, let url):
            var attr = AttributedString(title)
            attr.link = url
            attr.underlineStyle = .single
            return attr

        case .bold(let content):
            var attr = AttributedString(content)
            attr.inlinePresentationIntent = .stronglyEmphasized
            return attr

        case .italic(let content):
            var attr = AttributedString(content)
            attr.inlinePresentationIntent = .emphasized
            return attr

        case .underline(let content):
            var attr = AttributedString(content)
            attr.underlineStyle = .single
            return attr

        case .urlLink(let url, let content):
            var attr = AttributedString(content)
            if let url {
                attr.link = url
            }
            attr.underlineStyle = .single
            return attr
        }
    }
}
