//
//  CriticReview.swift
//  Playlist
//
//  The critic-review domain model (ADR 0012) and the shared wire-validation
//  policy both `PlaycutMetadataService`'s `/proxy/metadata/album` path and
//  the V2 flowsheet feed's inline `critic_reviews` decode apply to it.
//
//  Created by Jake Bromberg on 07/28/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A single attributed external critic-review snippet for an album (ADR 0012).
///
/// Mirrors the `CriticReviewItem` contract in `wxyc-shared/api.yaml`. The app
/// only ever holds the short excerpt plus its mandatory attribution and
/// link-out — never the full review body. `url` is non-optional precisely
/// because a card without a working link-out must not render (the attribution
/// guardrail); ``validated(_:)`` drops any served review whose URL can't be
/// parsed before this type is ever constructed.
///
/// Lives in `Playlist` (not `Metadata`, where it originated — see #566) so
/// that `Playcut.criticReviews` (this package) and `AlbumMetadata.criticReviews`
/// (`Metadata`, which depends on `Playlist`) share exactly one type: the inline
/// `PlaycutMetadataResolver.inlineMetadata(for:)` builder passes
/// `playcut.criticReviews` straight into `AlbumMetadata(criticReviews:)` with
/// no conversion (#695).
public struct CriticReview: Sendable, Equatable, Hashable, Codable {
    /// Publication name, e.g. "The Quietus". Always shown as attribution.
    public let source: String

    /// Link to the original review on the publisher's site (mandatory link-out).
    public let url: URL

    /// Short attributed excerpt (<= ~300 chars); never the full review body.
    public let snippet: String

    /// Review author, when available.
    public let author: String?

    /// Review publication date when available (e.g. "2024-03-15").
    public let publishedDate: String?

    /// Source-native rating string when available (e.g. "8.0").
    public let rating: String?

    public init(
        source: String,
        url: URL,
        snippet: String,
        author: String? = nil,
        publishedDate: String? = nil,
        rating: String? = nil
    ) {
        self.source = source
        self.url = url
        self.snippet = snippet
        self.author = author
        self.publishedDate = publishedDate
        self.rating = rating
    }
}

/// A loosely-typed wire shape for a single critic-review item, common to every
/// JSON representation that reuses `wxyc-shared`'s `CriticReviewItem` schema —
/// currently both `AlbumMetadataResponse.criticReviews` (the metadata proxy)
/// and `FlowsheetV2TrackEntry.critic_reviews` (the flowsheet feed, decoded by
/// hand in ``FlowsheetEntry`` since it predates that field in the generated
/// `WXYCAPIModels` package — see `docs/code-generation.md`).
///
/// Conforming a concrete wire type to this protocol is what lets
/// ``CriticReview/validated(_:)`` run the identical URL-validation policy
/// regardless of which decode path produced the item, instead of duplicating
/// the policy per call site.
public protocol CriticReviewItemWire {
    var source: String { get }
    var url: String { get }
    var snippet: String { get }
    var author: String? { get }
    var publishedDate: String? { get }
    var rating: String? { get }
}

public extension CriticReview {
    /// Validates one wire item against the mandatory link-out guarantee
    /// (ADR 0012) and constructs the domain review, or returns `nil` to drop
    /// the item.
    ///
    /// Trims `url`'s whitespace and requires the result be non-empty and
    /// parseable. `URL(string:)` alone is too lenient to use as the sole
    /// check — on modern Foundation it happily percent-encodes a
    /// whitespace-only string into a syntactically "valid" but useless URL —
    /// so an empty/whitespace value is the realistic bad-data case this
    /// guards against.
    ///
    /// This is the single URL-validation policy shared by every wire-decode
    /// path: `PlaycutMetadataService.mapCriticReviews` (the proxy path) and
    /// `FlowsheetEntry`'s tolerant `critic_reviews` decode (the feed path)
    /// both call through here rather than duplicating the trim/parse logic.
    static func validated(_ item: some CriticReviewItemWire) -> CriticReview? {
        let trimmed = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return CriticReview(
            source: item.source,
            url: url,
            snippet: item.snippet,
            author: item.author,
            publishedDate: item.publishedDate,
            rating: item.rating
        )
    }

    /// Maps a served/decoded list of wire items into domain reviews, running
    /// each through ``validated(_:)`` and dropping the ones that fail.
    ///
    /// Returns `nil` — not `[]` — when `items` is `nil`, empty, or every item
    /// failed validation, so the domain preserves the "no reviews attached"
    /// vs. "empty after filtering" nuance as an equivalent `nil`: both hide
    /// `ReviewsSection`, but `nil` avoids caching or round-tripping a
    /// pointless empty array.
    static func parsed<Wire: CriticReviewItemWire>(from items: [Wire]?) -> [CriticReview]? {
        guard let items, !items.isEmpty else { return nil }
        let reviews = items.compactMap { validated($0) }
        return reviews.isEmpty ? nil : reviews
    }
}
