//
//  OEmbedClient.swift
//  MusicShareKit
//
//  Shared oEmbed fetch-and-parse used by services (SoundCloud, YouTube) that expose an
//  oembed.com-compatible endpoint for track metadata.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

enum OEmbedClient {
    /// The fields this app reads out of an oEmbed JSON response. oEmbed responses carry more
    /// (type, width, height, provider info, ...); only these three are ever consulted.
    struct Response {
        let title: String?
        let authorName: String?
        let thumbnailURL: URL?

        static let empty = Response(title: nil, authorName: nil, thumbnailURL: nil)
    }

    /// Fetches and parses `endpoint?url=<trackURL>&format=json`.
    ///
    /// Returns `.empty` (not a throw) when the endpoint URL can't be constructed or the response
    /// body isn't a JSON object — callers treat that the same as "nothing new to merge in".
    /// A malformed JSON body still throws, same as before this was extracted: `JSONSerialization`
    /// itself may throw, and that propagates to the caller uncaught.
    ///
    /// `endpoint` is deliberately parsed with a `guard` rather than a force-unwrap: the callers
    /// this was extracted from force-unwrapped a string *literal*, which was safe by
    /// construction, but as a parameter it is no longer.
    static func fetch(endpoint: String, trackURL: URL, session: URLSession = .shared) async throws -> Response {
        guard var components = URLComponents(string: endpoint) else {
            return .empty
        }

        components.queryItems = [
            URLQueryItem(name: "url", value: trackURL.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let apiURL = components.url else {
            return .empty
        }

        let (data, _) = try await session.data(from: apiURL)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .empty
        }

        return Response(
            title: json["title"] as? String,
            authorName: json["author_name"] as? String,
            thumbnailURL: (json["thumbnail_url"] as? String).flatMap { URL(string: $0) }
        )
    }
}
