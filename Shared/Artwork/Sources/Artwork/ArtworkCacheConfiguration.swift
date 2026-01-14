//
//  ArtworkCacheConfiguration.swift
//  Artwork
//
//  Global configuration for artwork caching dimensions and compression.
//  Set at app launch based on screen size.
//
//  Created by Jake Bromberg on 01/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
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
