//
//  DiscogsMarkupParser.swift
//  Metadata
//
//  Created by Jake Bromberg on 12/7/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

// MARK: - DiscogsMarkupParser

/// Parser for Discogs formatting syntax
///
/// Discogs uses a special formatting syntax with square brackets for links and formatting.
/// This parser converts Discogs markup to AttributedString with proper formatting.
///
/// Supported formats:
/// - `[a=Artist Name]` - Artist links (displays the artist name)
/// - `[a12345]` - Artist link by ID (resolved via DiscogsEntityResolver)
/// - `[b]text[/b]` - Bold text
/// - `[i]text[/i]` - Italic text
/// - `[u]text[/u]` - Underlined text
/// - `[l=Label Name]` - Label links (displays the label name)
/// - `[url=http://example.com]Link Text[/url]` - URL links
/// - `[r12345]` - Release link by ID (resolved via DiscogsEntityResolver)
/// - `[m123]` - Master link by ID (resolved via DiscogsEntityResolver)
public struct DiscogsMarkupParser: Sendable {
    
    // MARK: - Synchronous API (no ID resolution)
    
    /// Parses Discogs formatting syntax and returns an AttributedString
    /// Note: ID-based tags ([a12345], [r12345], [m123]) are skipped without a resolver
    public static func parse(_ text: String) -> AttributedString {
        let tokens = tokenize(text)
        let resolved = resolve(tokens)
        return render(resolved)
    }
    
    // MARK: - Async API (with ID resolution)
    
    /// Parses Discogs formatting syntax and returns an AttributedString,
    /// resolving ID-based tags via the provided resolver
    public static func parse(_ text: String, resolver: DiscogsEntityResolver) async -> AttributedString {
        let tokens = tokenize(text)
        let resolved = await resolve(tokens, using: resolver)
        return render(resolved)
    }
    
    // MARK: - Utility
    
    /// Removes Discogs disambiguation suffix like " (8)" from artist names
    /// e.g., "Salamanda (8)" becomes "Salamanda"
    public static func stripDisambiguationSuffix(from name: String) -> String {
        // Pattern: ends with " (N)" where N is one or more digits
        let pattern = #" \(\d+\)$"#
        guard let range = name.range(of: pattern, options: .regularExpression) else {
            return name
        }
        return String(name[..<range.lowerBound])
    }
}

// MARK: - Token Types

extension DiscogsMarkupParser {
    
    /// Entity types that can be resolved
    
    /// Parsed token representing Discogs markup syntax (AST)
    /// Note: Formatting tags (bold, italic, underline, url) contain raw string content,
    /// not recursively parsed children, to match Discogs rendering behavior.
    enum DiscogsToken: Sendable {
        case plainText(String)
        case artistName(String)           // [a=Name]
        case artistId(Int)                // [a12345]
        case releaseId(Int)               // [r12345]
        case masterId(Int)                // [m123]
        case labelName(String)            // [l=Name]
        case bold(String)                 // [b]...[/b] - raw content
        case italic(String)               // [i]...[/i] - raw content
        case underline(String)            // [u]...[/u] - raw content
        case url(String, String)          // [url=...]...[/url] - URL and raw content
    }
    
    /// Resolved token with all IDs replaced by actual data
    enum ResolvedToken: Sendable {
        case plainText(String)
        case artistLink(name: String, displayName: String, url: URL)
        case labelName(String)
        case releaseLink(title: String, url: URL)
        case masterLink(title: String, url: URL)
        case bold(String)
        case italic(String)
        case underline(String)
        case urlLink(URL?, String)
    }
}

// MARK: - Regex Patterns

extension DiscogsMarkupParser {
    
    // Tag delimiter pattern - finds [...] (allows empty content)
    nonisolated(unsafe) private static let tagPattern = /\[([^\]]*)\]/
    
    // Tag classification patterns (applied to tag content)
    nonisolated(unsafe) private static let artistNamePattern = /^a=(.+)$/
    nonisolated(unsafe) private static let artistIdPattern = /^a(\d+)$/
    nonisolated(unsafe) private static let releaseIdPattern = /^r(\d+)$/
    nonisolated(unsafe) private static let masterIdPattern = /^m(\d+)$/
    nonisolated(unsafe) private static let labelNamePattern = /^l=(.+)$/
    nonisolated(unsafe) private static let urlOpenPattern = /^url=(.+)$/
    nonisolated(unsafe) private static let closingTagPattern = /^\/(.+)$/
}

// MARK: - Phase 1: Tokenize

extension DiscogsMarkupParser {
    
    /// Tokenizes Discogs markup into a flat list of tokens
    static func tokenize(_ text: String) -> [DiscogsToken] {
        var tokens: [DiscogsToken] = []
        var remaining = text[...]
        
        while !remaining.isEmpty {
            // First check if there's a '[' at all
            guard let bracketIndex = remaining.firstIndex(of: "[") else {
                // No brackets, add remaining as plain text
                tokens.append(.plainText(String(remaining)))
                break
            }
            
            // Add plain text before the bracket
            let beforeBracket = remaining[..<bracketIndex]
            if !beforeBracket.isEmpty {
                tokens.append(.plainText(String(beforeBracket)))
            }
            
            // Now look for the closing ']'
            guard let closingBracket = remaining[bracketIndex...].firstIndex(of: "]") else {
                // No closing bracket - match old behavior: append full remaining (including beforeBracket again)
                tokens.append(.plainText(String(remaining)))
                break
            }
            
            // Extract tag content (may be empty for "[]")
            let tagContent = String(remaining[remaining.index(after: bracketIndex)..<closingBracket])
            
            // Advance past the tag
            remaining = remaining[remaining.index(after: closingBracket)...]
            
            // Classify and handle the tag (empty tags return nil and are skipped)
            if !tagContent.isEmpty, let token = classifyTag(tagContent, remaining: &remaining) {
                tokens.append(token)
            }
            // Unknown/orphaned/empty tags are silently skipped
        }
        
        return tokens
    }
    
    /// Classifies a tag and returns the appropriate token
    private static func classifyTag(_ tag: String, remaining: inout Substring) -> DiscogsToken? {
        // Artist name: [a=Name]
        if let match = tag.wholeMatch(of: artistNamePattern) {
            return .artistName(String(match.1))
        }
        
        // Artist ID: [a12345]
        if let match = tag.wholeMatch(of: artistIdPattern), let id = Int(match.1) {
            return .artistId(id)
        }
        
        // Release ID: [r12345]
        if let match = tag.wholeMatch(of: releaseIdPattern), let id = Int(match.1) {
            return .releaseId(id)
        }
        
        // Master ID: [m123]
        if let match = tag.wholeMatch(of: masterIdPattern), let id = Int(match.1) {
            return .masterId(id)
        }
        
        // Label name: [l=Name]
        if let match = tag.wholeMatch(of: labelNamePattern) {
            return .labelName(String(match.1))
        }
        
        // URL: [url=...]...[/url]
        if let match = tag.wholeMatch(of: urlOpenPattern) {
            let urlString = String(match.1)
            if let (content, newRemaining) = findClosingTag(in: remaining, tag: "url") {
                remaining = newRemaining
                return .url(urlString, content)
            } else {
                // No closing tag - show URL and remaining text combined
                let content = String(remaining)
                remaining = remaining[remaining.endIndex...]
                return .plainText(urlString + content)
            }
        }
        
        // Bold: [b]...[/b]
        if tag == "b" {
            if let (content, newRemaining) = findClosingTag(in: remaining, tag: "b") {
                remaining = newRemaining
                return .bold(content)
            } else {
                // No closing tag, skip
                return nil
            }
        }
        
        // Italic: [i]...[/i]
        if tag == "i" {
            if let (content, newRemaining) = findClosingTag(in: remaining, tag: "i") {
                remaining = newRemaining
                return .italic(content)
            } else {
                return nil
            }
        }
        
        // Underline: [u]...[/u]
        if tag == "u" {
            if let (content, newRemaining) = findClosingTag(in: remaining, tag: "u") {
                remaining = newRemaining
                return .underline(content)
            } else {
                return nil
            }
        }
        
        // Orphaned closing tags - skip
        if tag.wholeMatch(of: closingTagPattern) != nil {
            return nil
        }
        
        // Unknown tag - skip
        return nil
    }
    
    /// Finds a closing tag like [/tag] in the remaining text, handling same-type nesting via depth tracking.
    /// Returns the content between tags and the remaining substring after the closing tag.
    private static func findClosingTag(in text: Substring, tag: String) -> (content: String, remaining: Substring)? {
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
                    let content = String(text[..<openBracket])
                    let remaining = text[text.index(after: closeBracket)...]
                    return (content, remaining)
                }
            }
            
            searchStart = text.index(after: closeBracket)
        }
        
        return nil
    }
}

// MARK: - Phase 2: Resolve

extension DiscogsMarkupParser {
    
    /// Resolves tokens without a resolver (skips ID-based tokens)
    static func resolve(_ tokens: [DiscogsToken]) -> [ResolvedToken] {
        let emptyIds: [String: String] = [:]
        return tokens.compactMap { resolveToken($0, resolvedIds: emptyIds) }
    }
    
    /// Resolves tokens with a resolver (fetches ID-based data)
    static func resolve(_ tokens: [DiscogsToken], using resolver: DiscogsEntityResolver) async -> [ResolvedToken] {
        // Collect all IDs from the tokens
        var artistIds: Set<Int> = []
        var releaseIds: Set<Int> = []
        var masterIds: Set<Int> = []
        
        for token in tokens {
            switch token {
            case .artistId(let id):
                artistIds.insert(id)
            case .releaseId(let id):
                releaseIds.insert(id)
            case .masterId(let id):
                masterIds.insert(id)
            default:
                break
            }
        }
        
        // Resolve all IDs concurrently
        let resolvedIds = await withTaskGroup(of: (String, String?).self) { group in
            for id in artistIds {
                group.addTask {
                    let name = try? await resolver.resolveArtist(id: id)
                    return ("artist-\(id)", name)
                }
            }
            for id in releaseIds {
                group.addTask {
                    let title = try? await resolver.resolveRelease(id: id)
                    return ("release-\(id)", title)
                }
            }
            for id in masterIds {
                group.addTask {
                    let title = try? await resolver.resolveMaster(id: id)
                    return ("master-\(id)", title)
                }
            }
            
            var results: [String: String] = [:]
            for await (key, value) in group {
                if let value {
                    results[key] = value
                }
            }
            return results
        }
        
        // Rebuild with resolved values
        return tokens.compactMap { resolveToken($0, resolvedIds: resolvedIds) }
    }
    
    /// Resolves a single token using the resolved ID map
    private static func resolveToken(_ token: DiscogsToken, resolvedIds: [String: String]) -> ResolvedToken? {
        switch token {
        case .plainText(let text):
            return .plainText(text)
            
        case .artistName(let name):
            let displayName = stripDisambiguationSuffix(from: name)
            let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
            let url = URL(string: "https://www.discogs.com/search/?q=\(encodedName)&type=artist")!
            return .artistLink(name: name, displayName: displayName, url: url)
            
        case .artistId(let id):
            guard let name = resolvedIds["artist-\(id)"] else {
                return nil // Skip unresolved
            }
            let displayName = stripDisambiguationSuffix(from: name)
            let url = URL(string: "https://www.discogs.com/artist/\(id)")!
            return .artistLink(name: name, displayName: displayName, url: url)
            
        case .releaseId(let id):
            guard let title = resolvedIds["release-\(id)"] else {
                return nil // Skip unresolved
            }
            let url = URL(string: "https://www.discogs.com/release/\(id)")!
            return .releaseLink(title: title, url: url)
            
        case .masterId(let id):
            guard let title = resolvedIds["master-\(id)"] else {
                return nil // Skip unresolved
            }
            let url = URL(string: "https://www.discogs.com/master/\(id)")!
            return .masterLink(title: title, url: url)
            
        case .labelName(let name):
            return .labelName(name)
            
        case .bold(let content):
            return .bold(content)
            
        case .italic(let content):
            return .italic(content)
            
        case .underline(let content):
            return .underline(content)
            
        case .url(let urlString, let content):
            let url = URL(string: urlString)
            return .urlLink(url, content)
        }
    }
}

// MARK: - Phase 3: Render

extension DiscogsMarkupParser {
    
    /// Renders resolved tokens to AttributedString
    static func render(_ tokens: [ResolvedToken]) -> AttributedString {
        tokens.reduce(into: AttributedString()) { result, token in
            result.append(renderToken(token))
        }
    }
    
    /// Renders a single resolved token
    private static func renderToken(_ token: ResolvedToken) -> AttributedString {
        switch token {
        case .plainText(let text):
            return AttributedString(text)
            
        case .artistLink(_, let displayName, let url):
            var attr = AttributedString(displayName)
            attr.link = url
            attr.underlineStyle = .single
            return attr
            
        case .labelName(let name):
            return AttributedString(name)
            
        case .releaseLink(let title, let url):
            var attr = AttributedString(title)
            attr.link = url
            attr.underlineStyle = .single
            return attr
            
        case .masterLink(let title, let url):
            var attr = AttributedString(title)
            attr.link = url
            attr.underlineStyle = .single
            return attr
            
        case .bold(let content):
            var attr = AttributedString(content)
            attr.inlinePresentationIntent = .stronglyEmphasized
            return attr
            
        case .italic(let content):
            var attr = AttributedString(content)
            attr.inlinePresentationIntent = .emphasized
            return attr
            
        case .underline(let content):
            var attr = AttributedString(content)
            attr.underlineStyle = .single
            return attr
            
        case .urlLink(let url, let content):
            var attr = AttributedString(content)
            if let url {
                attr.link = url
            }
            attr.underlineStyle = .single
            return attr
        }
    }
}
