//
//  ArtworkCacheConfiguration.swift
//  Artwork
//
//  Created by Jake Bromberg on 1/9/26.
//

import Foundation

/// Configuration for artwork caching behavior.
public enum ArtworkCacheConfiguration {
    /// Target width for cached artwork. Set at app startup based on screen dimensions.
    /// - Note: Set once at app launch, read-only thereafter.
    public nonisolated(unsafe) static var targetWidth: CGFloat = 430

    /// HEIF compression quality (0.0 - 1.0). Higher values mean better quality but larger files.
    /// - Note: Set once at app launch, read-only thereafter.
    public nonisolated(unsafe) static var heifCompressionQuality: CGFloat = 0.8
}
