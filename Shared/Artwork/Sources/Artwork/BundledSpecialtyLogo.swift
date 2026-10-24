//
//  BundledSpecialtyLogo.swift
//  Artwork
//
//  A DEBUG-only fallback that bundles a specialty program's permanent logo, keyed
//  by program slug, until the server-side logo upload path ships. Holds only New
//  Science Experience. Release builds never resolve a bundled logo.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics
import Foundation
import ImageIO
import Playlist

extension SpecialtyArtwork {
    /// The bundled logo for `program`, or `nil` when the program has a server logo URL (a server logo always
    /// wins), its slug has no bundled logo, or this is not a DEBUG build. Decoded no larger than `maxPixelSize`
    /// (by default the artwork cache's target width) on its longest side, like a downloaded logo.
    public static func bundledLogo(for program: SpecialtyShowRef, maxPixelSize: Int = Int(ArtworkCacheConfiguration.targetWidth)) -> CGImage? {
        #if DEBUG
        guard logoURL(for: program) == nil, let data = BundledSpecialtyLogo.data[program.slug] else { return nil }
        return decodeLogo(from: data, maxPixelSize: maxPixelSize)
        #else
        return nil
        #endif
    }
}

#if DEBUG
/// Bundled logo images by program slug. Remove an entry once its program has a server logo.
enum BundledSpecialtyLogo {
    /// Resource names (without extension) in the Artwork bundle's `Resources` folder.
    private static let resourceNames = [
        // New Science Experience: permanent show logo, decided 2026-10-23 (Backend-Service#3445, #3475).
        "new-science-experience": "nse-logo",
    ]

    /// The encoded bytes, so each caller decodes at the size it needs.
    static let data: [String: Data] = resourceNames.compactMapValues { name in
        Bundle.module.url(forResource: name, withExtension: "png").flatMap { try? Data(contentsOf: $0) }
    }
}
#endif
