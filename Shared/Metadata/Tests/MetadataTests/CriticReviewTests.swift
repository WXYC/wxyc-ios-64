//
//  CriticReviewTests.swift
//  Metadata
//
//  Tests for the CriticReview domain model and its album-metadata gating.
//
//  Created by Jake Bromberg on 07/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Metadata

@Suite("CriticReview Tests")
struct CriticReviewTests {

    // MARK: - Codable

    @Test("CriticReview encodes and decodes with all fields")
    func encodesDecodesFull() throws {
        let review = CriticReview(
            source: "The Quietus",
            url: URL(string: "https://thequietus.com/articles/12345")!,
            snippet: "A restless, shape-shifting record that never settles.",
            author: "Jane Critic",
            publishedDate: "2024-03-15",
            rating: "8.0"
        )

        let encoded = try JSONEncoder().encode(review)
        let decoded = try JSONDecoder().decode(CriticReview.self, from: encoded)

        #expect(decoded == review)
        #expect(decoded.source == "The Quietus")
        #expect(decoded.url.absoluteString == "https://thequietus.com/articles/12345")
        #expect(decoded.snippet == "A restless, shape-shifting record that never settles.")
        #expect(decoded.author == "Jane Critic")
        #expect(decoded.publishedDate == "2024-03-15")
        #expect(decoded.rating == "8.0")
    }

    @Test("CriticReview decodes with only required fields; optionals default to nil")
    func decodesRequiredOnly() throws {
        let json = """
        {"source": "The Quietus", "url": "https://thequietus.com/a/1", "snippet": "Great."}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CriticReview.self, from: json)

        #expect(decoded.source == "The Quietus")
        #expect(decoded.url.absoluteString == "https://thequietus.com/a/1")
        #expect(decoded.snippet == "Great.")
        #expect(decoded.author == nil)
        #expect(decoded.publishedDate == nil)
        #expect(decoded.rating == nil)
    }

    // MARK: - AlbumMetadata gating

    @Test("AlbumMetadata.hasCriticReviews is true only when reviews are non-empty")
    func hasCriticReviewsGate() {
        let review = CriticReview(
            source: "The Quietus",
            url: URL(string: "https://thequietus.com/a/1")!,
            snippet: "x"
        )

        #expect(AlbumMetadata(criticReviews: [review]).hasCriticReviews == true)
        #expect(AlbumMetadata(criticReviews: []).hasCriticReviews == false)
        #expect(AlbumMetadata(criticReviews: nil).hasCriticReviews == false)
        #expect(AlbumMetadata.empty.hasCriticReviews == false)
    }

    @Test("AlbumMetadata round-trips criticReviews through Codable")
    func albumMetadataCarriesCriticReviews() throws {
        let review = CriticReview(
            source: "The Quietus",
            url: URL(string: "https://thequietus.com/a/1")!,
            snippet: "x",
            publishedDate: "2024-01-01"
        )
        let album = AlbumMetadata(label: "Drag City", criticReviews: [review])

        let decoded = try JSONDecoder().decode(AlbumMetadata.self, from: JSONEncoder().encode(album))

        #expect(decoded == album)
        #expect(decoded.criticReviews?.count == 1)
        #expect(decoded.criticReviews?.first?.source == "The Quietus")
    }

    @Test("AlbumMetadata decoded without a criticReviews key leaves it nil (cache back-compat)")
    func albumMetadataBackwardCompatibleDecoding() throws {
        let json = """
        {"label": "Drag City", "releaseYear": 2015}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AlbumMetadata.self, from: json)

        #expect(decoded.label == "Drag City")
        #expect(decoded.criticReviews == nil)
        #expect(decoded.hasCriticReviews == false)
    }

    @Test("criticReviews never flip hasMetadataSectionContent (Reviews gates independently)")
    func criticReviewsDoNotFlipMetadataSection() {
        let review = CriticReview(
            source: "The Quietus",
            url: URL(string: "https://thequietus.com/a/1")!,
            snippet: "x"
        )
        let metadata = PlaycutMetadata(album: AlbumMetadata(criticReviews: [review]))

        #expect(metadata.hasMetadataSectionContent == false)
        #expect(metadata.album.hasCriticReviews == true)
    }
}
