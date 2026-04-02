//
//  URLArtworkFetcher.swift
//  Artwork
//
//  Downloads album artwork from a URL provided by the v2 flowsheet API.
//  The simplest artwork fetcher: given a playcut with an artworkURL, fetch the image.
//
//  Created by Jake Bromberg on 03/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Core
import CoreGraphics
import Playlist

/// Fetches artwork by downloading the image at the playcut's `artworkURL`.
///
/// This is the primary fetcher for v2 API responses where the backend has already
/// resolved the artwork URL during metadata enrichment. Falls through with
/// `ServiceError.noResults` when the playcut has no artwork URL (e.g., v1 entries
/// or entries where enrichment hasn't completed yet).
final class URLArtworkFetcher: ArtworkService {
    private let session: WebSession

    init(session: WebSession = URLSession.shared) {
        self.session = session
    }

    func fetchArtwork(for playcut: Playcut) async throws -> CGImage {
        guard let url = playcut.artworkURL else {
            throw ServiceError.noResults
        }

        let data = try await session.data(from: url)

        guard let image = createCGImage(from: data) else {
            throw ServiceError.noResults
        }

        return image
    }
}
