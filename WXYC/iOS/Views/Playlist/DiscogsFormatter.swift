//
//  DiscogsFormatter.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

// MARK: - Entity Resolver Protocol

/// Protocol for resolving Discogs entity IDs to their display names
protocol DiscogsEntityResolver: Sendable {
    /// Resolves an artist ID to the artist's name
    func resolveArtist(id: Int) async throws -> String
    
    /// Resolves a release ID to the release title
    func resolveRelease(id: Int) async throws -> String
    
    /// Resolves a master release ID to the master title
    func resolveMaster(id: Int) async throws -> String
}

// MARK: - DiscogsFormatter

/// Parser for Discogs formatting syntax
/// 
/// Discogs uses a special formatting syntax with square brackets for links and formatting.
/// This parser converts Discogs markup to SwiftUI Text with proper formatting.
/// 
/// Supported formats:
/// - `[a=Artist Name]` - Artist links (displays the artist name)
/// - `[a12345]` - Artist link by ID (resolved via DiscogsEntityResolver)
/// - `[b]text[/b]` - Bold text
/// - `[i]text[/i]` - Italic text
/// - `[u]text[/u]` - Underlined text
/// - `[l=Label Name]` - Label links (displays the label name)
/// - `[url=http://example.com]Link Text[/url]` - URL links (styled as secondary underlined text)
/// - `[r12345]` - Release link by ID (resolved via DiscogsEntityResolver)
/// - `[m123]` - Master link by ID (resolved via DiscogsEntityResolver)
struct DiscogsFormatter {
    
    // MARK: - Synchronous API (no ID resolution)
    
    /// Parses Discogs formatting syntax and converts it to SwiftUI Text
    /// Note: ID-based tags ([a12345], [r12345], [m123]) are skipped without a resolver
    static func parse(_ text: String) -> Text {
        Text(parseToAttributedString(text))
    }
    
    /// Parses Discogs formatting syntax and returns an AttributedString
    /// Note: ID-based tags ([a12345], [r12345], [m123]) are skipped without a resolver
    static func parseToAttributedString(_ text: String) -> AttributedString {
        // Use internal parser with no resolver - IDs will be skipped
        let parser = Parser(text: text, resolver: nil)
        return parser.parse()
    }
    
    // MARK: - Async API (with ID resolution)
    
    /// Parses Discogs formatting syntax and converts it to SwiftUI Text,
    /// resolving ID-based tags via the provided resolver
    static func parse(_ text: String, resolver: DiscogsEntityResolver) async -> Text {
        Text(await parseToAttributedString(text, resolver: resolver))
    }
    
    /// Parses Discogs formatting syntax and returns an AttributedString,
    /// resolving ID-based tags via the provided resolver
    static func parseToAttributedString(_ text: String, resolver: DiscogsEntityResolver) async -> AttributedString {
        let parser = Parser(text: text, resolver: resolver)
        return await parser.parseAsync()
    }
}

// MARK: - Internal Parser

private extension DiscogsFormatter {
    
    /// Entity types that can be resolved
    enum EntityType {
        case artist
        case release
        case master
    }
    
    /// Represents an ID-based tag that needs resolution
    struct PendingResolution {
        let type: EntityType
        let id: Int
        let insertionIndex: Int  // Position in the result where resolved name should be inserted
    }
    
    /// Represents a resolved entity with its display name and link URL
    struct ResolvedEntity {
        let name: String
        let type: EntityType
        let id: Int
        
        /// The display name, with Discogs disambiguation suffix removed for artists
        /// e.g., "Salamanda (8)" becomes "Salamanda"
        var displayName: String {
            switch type {
            case .artist:
                return DiscogsFormatter.stripDisambiguationSuffix(from: name)
            case .release, .master:
                return name
            }
        }
        
        /// Constructs the Discogs URL for this entity
        var discogsURL: URL {
            switch type {
            case .artist:
                return URL(string: "https://www.discogs.com/artist/\(id)")!
            case .release:
                return URL(string: "https://www.discogs.com/release/\(id)")!
            case .master:
                return URL(string: "https://www.discogs.com/master/\(id)")!
            }
        }
        
    }
    
    /// Removes Discogs disambiguation suffix like " (8)" from artist names
    /// e.g., "Salamanda (8)" becomes "Salamanda"
    static func stripDisambiguationSuffix(from name: String) -> String {
        // Pattern: ends with " (N)" where N is one or more digits
        let pattern = #" \(\d+\)$"#
        guard let range = name.range(of: pattern, options: .regularExpression) else {
            return name
        }
        return String(name[..<range.lowerBound])
    }
    
    /// Internal parser that handles both sync and async parsing
    struct Parser {
        let text: String
        let resolver: DiscogsEntityResolver?
        
        /// Synchronous parse - skips ID-based tags
        func parse() -> AttributedString {
            var result = AttributedString()
            var remaining = text[...]
            
            while !remaining.isEmpty {
                if let bracketIndex = remaining.firstIndex(of: "[") {
                    // Add text before the bracket
                    let beforeBracket = remaining[..<bracketIndex]
                    if !beforeBracket.isEmpty {
                        result.append(AttributedString(String(beforeBracket)))
                    }
                    
                    if let closingBracket = remaining[bracketIndex...].firstIndex(of: "]") {
                        let tagContent = remaining[remaining.index(after: bracketIndex)..<closingBracket]
                        let tag = String(tagContent)
                        
                        let parseResult = handleTag(tag, remaining: remaining, closingBracket: closingBracket)
                        if let attributed = parseResult.attributed {
                            result.append(attributed)
                        }
                        remaining = parseResult.newRemaining
                    } else {
                        result.append(AttributedString(String(remaining)))
                        break
                    }
                } else {
                    result.append(AttributedString(String(remaining)))
                    break
                }
            }
            
            return result
        }
        
        /// Async parse - resolves ID-based tags via resolver
        func parseAsync() async -> AttributedString {
            // First pass: parse and collect pending resolutions
            var result = AttributedString()
            var remaining = text[...]
            var pendingResolutions: [PendingResolution] = []
            
            while !remaining.isEmpty {
                if let bracketIndex = remaining.firstIndex(of: "[") {
                    let beforeBracket = remaining[..<bracketIndex]
                    if !beforeBracket.isEmpty {
                        result.append(AttributedString(String(beforeBracket)))
                    }
                    
                    if let closingBracket = remaining[bracketIndex...].firstIndex(of: "]") {
                        let tagContent = remaining[remaining.index(after: bracketIndex)..<closingBracket]
                        let tag = String(tagContent)
                        
                        // Check for ID-based tags
                        if let resolution = checkForIdTag(tag) {
                            // Record position and add placeholder
                            let placeholder = AttributedString("") // Will be replaced
                            pendingResolutions.append(PendingResolution(
                                type: resolution.type,
                                id: resolution.id,
                                insertionIndex: result.characters.count
                            ))
                            result.append(placeholder)
                            remaining = remaining[remaining.index(after: closingBracket)...]
                        } else {
                            let parseResult = handleTag(tag, remaining: remaining, closingBracket: closingBracket)
                            if let attributed = parseResult.attributed {
                                result.append(attributed)
                            }
                            remaining = parseResult.newRemaining
                        }
                    } else {
                        result.append(AttributedString(String(remaining)))
                        break
                    }
                } else {
                    result.append(AttributedString(String(remaining)))
                    break
                }
            }
            
            // Second pass: resolve IDs concurrently and rebuild
            guard let resolver = resolver, !pendingResolutions.isEmpty else {
                return result
            }
            
            // Resolve all IDs concurrently
            let resolvedEntities = await withTaskGroup(of: (Int, ResolvedEntity?).self) { group in
                for (index, pending) in pendingResolutions.enumerated() {
                    group.addTask {
                        let entity: ResolvedEntity?
                        do {
                            switch pending.type {
                            case .artist:
                                let name = try await resolver.resolveArtist(id: pending.id)
                                entity = ResolvedEntity(name: name, type: .artist, id: pending.id)
                            case .release:
                                let name = try await resolver.resolveRelease(id: pending.id)
                                entity = ResolvedEntity(name: name, type: .release, id: pending.id)
                            case .master:
                                let name = try await resolver.resolveMaster(id: pending.id)
                                entity = ResolvedEntity(name: name, type: .master, id: pending.id)
                            }
                        } catch {
                            entity = nil
                        }
                        return (index, entity)
                    }
                }
                
                var entities: [Int: ResolvedEntity?] = [:]
                for await (index, entity) in group {
                    entities[index] = entity
                }
                return entities
            }
            
            // Rebuild with resolved names (parse again with resolved values)
            var finalResult = AttributedString()
            remaining = text[...]
            var resolutionIndex = 0
            
            while !remaining.isEmpty {
                if let bracketIndex = remaining.firstIndex(of: "[") {
                    let beforeBracket = remaining[..<bracketIndex]
                    if !beforeBracket.isEmpty {
                        finalResult.append(AttributedString(String(beforeBracket)))
                    }
                    
                    if let closingBracket = remaining[bracketIndex...].firstIndex(of: "]") {
                        let tagContent = remaining[remaining.index(after: bracketIndex)..<closingBracket]
                        let tag = String(tagContent)
                        
                        if checkForIdTag(tag) != nil {
                            // Insert resolved name with link
                            if let entity = resolvedEntities[resolutionIndex] ?? nil {
                                var attributed = AttributedString(entity.displayName)
                                attributed.link = entity.discogsURL
                                attributed.foregroundColor = .secondary
                                attributed.underlineStyle = .single
                                finalResult.append(attributed)
                            }
                            resolutionIndex += 1
                            remaining = remaining[remaining.index(after: closingBracket)...]
                        } else {
                            let parseResult = handleTag(tag, remaining: remaining, closingBracket: closingBracket)
                            if let attributed = parseResult.attributed {
                                finalResult.append(attributed)
                            }
                            remaining = parseResult.newRemaining
                        }
                    } else {
                        finalResult.append(AttributedString(String(remaining)))
                        break
                    }
                } else {
                    finalResult.append(AttributedString(String(remaining)))
                    break
                }
            }
            
            return finalResult
        }
        
        /// Checks if a tag is an ID-based tag and returns its type and ID
        private func checkForIdTag(_ tag: String) -> (type: EntityType, id: Int)? {
            if tag.hasPrefix("a") && tag.count > 1 && tag.dropFirst().allSatisfy(\.isNumber) {
                if let id = Int(tag.dropFirst()) {
                    return (.artist, id)
                }
            } else if tag.hasPrefix("r") && tag.count > 1 && tag.dropFirst().allSatisfy(\.isNumber) {
                if let id = Int(tag.dropFirst()) {
                    return (.release, id)
                }
            } else if tag.hasPrefix("m") && tag.count > 1 && tag.dropFirst().allSatisfy(\.isNumber) {
                if let id = Int(tag.dropFirst()) {
                    return (.master, id)
                }
            }
            return nil
        }
        
        /// Handles a single tag and returns the attributed string and new remaining substring
        private func handleTag(
            _ tag: String,
            remaining: Substring,
            closingBracket: String.Index
        ) -> (attributed: AttributedString?, newRemaining: Substring) {
            
            if tag.hasPrefix("a=") {
                // Artist link: [a=Artist Name] -> show name with disambiguation suffix removed, link to Discogs search
                let artistName = String(tag.dropFirst(2))
                let displayName = DiscogsFormatter.stripDisambiguationSuffix(from: artistName)
                var attributed = AttributedString(displayName)
                // Use original name (with disambiguation) for search to find the exact artist
                if let encodedName = artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    attributed.link = URL(string: "https://www.discogs.com/search/?q=\(encodedName)&type=artist")
                }
                attributed.foregroundColor = .secondary
                attributed.underlineStyle = .single
                return (attributed, remaining[remaining.index(after: closingBracket)...])
                
            } else if tag.hasPrefix("a") && tag.count > 1 && tag.dropFirst().allSatisfy(\.isNumber) {
                // Artist link by ID: [a12345] -> skip in sync mode
                return (nil, remaining[remaining.index(after: closingBracket)...])
                
            } else if tag == "b" {
                // Bold start: [b]...[/b]
                if let endTag = DiscogsFormatter.findClosingTag(in: remaining[remaining.index(after: closingBracket)...], tag: "b") {
                    let boldText = String(remaining[remaining.index(after: closingBracket)..<endTag.startIndex])
                    var attributed = AttributedString(boldText)
                    attributed.inlinePresentationIntent = .stronglyEmphasized
                    return (attributed, remaining[endTag.endIndex...])
                } else {
                    return (nil, remaining[remaining.index(after: closingBracket)...])
                }
                
            } else if tag == "/b" {
                // Bold end (orphaned closing tag, skip it)
                return (nil, remaining[remaining.index(after: closingBracket)...])
                
            } else if tag == "i" {
                // Italic start: [i]...[/i]
                if let endTag = DiscogsFormatter.findClosingTag(in: remaining[remaining.index(after: closingBracket)...], tag: "i") {
                    let italicText = String(remaining[remaining.index(after: closingBracket)..<endTag.startIndex])
                    var attributed = AttributedString(italicText)
                    attributed.inlinePresentationIntent = .emphasized
                    return (attributed, remaining[endTag.endIndex...])
                } else {
                    return (nil, remaining[remaining.index(after: closingBracket)...])
                }
                
            } else if tag == "/i" {
                // Italic end (orphaned closing tag, skip it)
                return (nil, remaining[remaining.index(after: closingBracket)...])
                
            } else if tag == "u" {
                // Underline start: [u]...[/u]
                if let endTag = DiscogsFormatter.findClosingTag(in: remaining[remaining.index(after: closingBracket)...], tag: "u") {
                    let underlineText = String(remaining[remaining.index(after: closingBracket)..<endTag.startIndex])
                    var attributed = AttributedString(underlineText)
                    attributed.underlineStyle = .single
                    return (attributed, remaining[endTag.endIndex...])
                } else {
                    return (nil, remaining[remaining.index(after: closingBracket)...])
                }
                
            } else if tag == "/u" {
                // Underline end (orphaned closing tag, skip it)
                return (nil, remaining[remaining.index(after: closingBracket)...])
                
            } else if tag.hasPrefix("l=") {
                // Label link: [l=Label Name] -> just show the name
                let labelName = String(tag.dropFirst(2))
                return (AttributedString(labelName), remaining[remaining.index(after: closingBracket)...])
                
            } else if tag.hasPrefix("url=") {
                // URL link: [url=http://example.com]Link Text[/url]
                let urlString = String(tag.dropFirst(4))
                if let urlEndTag = DiscogsFormatter.findClosingTag(in: remaining[remaining.index(after: closingBracket)...], tag: "url") {
                    let linkText = String(remaining[remaining.index(after: closingBracket)..<urlEndTag.startIndex])
                    var attributed = AttributedString(linkText)
                    if let url = URL(string: urlString) {
                        attributed.link = url
                    }
                    attributed.foregroundColor = .secondary
                    attributed.underlineStyle = .single
                    return (attributed, remaining[urlEndTag.endIndex...])
                } else {
                    // No closing tag, just show the URL
                    return (AttributedString(urlString), remaining[remaining.index(after: closingBracket)...])
                }
                
            } else if tag.hasPrefix("r") && tag.count > 1 && tag.dropFirst().allSatisfy(\.isNumber) {
                // Release link by ID: [r12345] -> skip in sync mode
                return (nil, remaining[remaining.index(after: closingBracket)...])
                
            } else if tag.hasPrefix("m") && tag.count > 1 && tag.dropFirst().allSatisfy(\.isNumber) {
                // Master link by ID: [m123] -> skip in sync mode
                return (nil, remaining[remaining.index(after: closingBracket)...])
                
            } else {
                // Unknown tag, skip it
                return (nil, remaining[remaining.index(after: closingBracket)...])
            }
        }
    }
    
    /// Finds a closing tag like [/tag] in the remaining text, handling nested tags
    static func findClosingTag(in text: Substring, tag: String) -> (startIndex: String.Index, endIndex: String.Index)? {
        var searchStart = text.startIndex
        var depth = 1
        
        while searchStart < text.endIndex {
            guard let openBracket = text[searchStart...].firstIndex(of: "["),
                  let closeBracket = text[openBracket...].firstIndex(of: "]") else {
                break
            }
            
            let tagContent = text[text.index(after: openBracket)..<closeBracket]
            let currentTag = String(tagContent)
            
            if currentTag == tag {
                depth += 1
            } else if currentTag == "/\(tag)" {
                depth -= 1
                if depth == 0 {
                    return (openBracket, text.index(after: closeBracket))
                }
            }
            
            searchStart = text.index(after: closeBracket)
        }
        
        return nil
    }
}
