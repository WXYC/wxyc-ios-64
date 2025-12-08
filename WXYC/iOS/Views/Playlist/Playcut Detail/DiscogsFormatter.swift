//
//  DiscogsFormatter.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Metadata

// MARK: - DiscogsFormatter

/// Formats parsed Discogs markup as SwiftUI Text with platform-specific styling
///
/// This wrapper applies SwiftUI-specific styling (like secondary color for links)
/// on top of the Foundation-based `DiscogsMarkupParser`.
struct DiscogsFormatter {
    
    // MARK: - Synchronous API (no ID resolution)
    
    /// Parses Discogs formatting syntax and converts it to SwiftUI Text
    /// Note: ID-based tags ([a12345], [r12345], [m123]) are skipped without a resolver
    static func parse(_ text: String) -> Text {
        Text(parseToAttributedString(text))
    }
    
    /// Parses Discogs formatting syntax and returns an AttributedString with SwiftUI styling
    /// Note: ID-based tags ([a12345], [r12345], [m123]) are skipped without a resolver
    static func parseToAttributedString(_ text: String) -> AttributedString {
        applyLinkStyling(to: DiscogsMarkupParser.parse(text))
    }
    
    // MARK: - Async API (with ID resolution)
    
    /// Parses Discogs formatting syntax and converts it to SwiftUI Text,
    /// resolving ID-based tags via the provided resolver
    
    /// Parses Discogs formatting syntax and returns an AttributedString with SwiftUI styling,
    /// resolving ID-based tags via the provided resolver
    static func parseToAttributedString(_ text: String, resolver: DiscogsEntityResolver) async -> AttributedString {
        applyLinkStyling(to: await DiscogsMarkupParser.parse(text, resolver: resolver))
    }
    
    // MARK: - Private
    
    /// Applies SwiftUI-specific styling to links (secondary foreground color)
    private static func applyLinkStyling(to attributedString: AttributedString) -> AttributedString {
        var result = attributedString
        
        for run in result.runs {
            if run.link != nil {
                let range = run.range
                result[range].foregroundColor = .secondary
            }
        }
        
        return result
    }
}
