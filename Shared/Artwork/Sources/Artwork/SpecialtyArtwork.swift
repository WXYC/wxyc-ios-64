//
//  SpecialtyArtwork.swift
//  Artwork
//
//  The specialty program's logo: which URL to load, when to fall back to the
//  text tile, and the URL-keyed entry point into the shared artwork cache.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Caching
import CoreGraphics
import Core
import Logger
import Playlist

/// The pure decisions behind `SpecialtyArtworkView`, kept free of SwiftUI and the network so a table can test them.
public enum SpecialtyArtwork {
    public enum LogoState: Sendable {
        case loading, loaded, failed
    }

    /// The logo to load for `program`, or `nil` when it has none and the tile is all there is.
    public static func logoURL(for program: SpecialtyShowRef) -> URL? {
        program.artwork?.squareURL
    }

    /// Whether to draw the logo rather than the tile: only once a logo URL exists and its image has loaded.
    public static func showsLogo(url: URL?, state: LogoState) -> Bool {
        url != nil && state == .loaded
    }

    /// How long a downloaded logo stays cached.
    static let lifespan: TimeInterval = 30 * 24 * 60 * 60
}

extension CacheCoordinator {
    /// Returns the image at `url`, from this cache when present, otherwise downloaded with `session` and stored.
    ///
    /// The URL string is the cache key, so the same logo is never fetched twice while it is cached. Failures
    /// throw and are never cached, so a transient error does not pin the tile.
    func image(from url: URL, session: any WebSession = URLSession.shared) async throws -> CGImage {
        let key = url.absoluteString
        if let cached = try? data(for: key), let image = createCGImage(from: cached) {
            return image
        }
        do {
            let image = try await createCGImage(from: session.data(from: url)).orThrow(ServiceError.noResults)
            await set(artwork: image, for: key, lifespan: SpecialtyArtwork.lifespan)
            return image
        } catch {
            Log(.warning, category: .artwork, "Specialty logo fetch failed for \(key): \(error)")
            throw error
        }
    }
}

private extension Optional {
    func orThrow(_ error: any Error) throws -> Wrapped {
        guard let self else { throw error }
        return self
    }
}
