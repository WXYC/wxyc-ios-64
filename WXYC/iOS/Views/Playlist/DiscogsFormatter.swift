//
//  DiscogsFormatter.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

/// Parser for Discogs formatting syntax
/// 
/// Discogs uses a special formatting syntax with square brackets for links and formatting.
/// This parser converts Discogs markup to SwiftUI Text with proper formatting.
/// 
/// Supported formats:
/// - `[a=Artist Name]` - Artist links (displays the artist name)
/// - `[b]text[/b]` - Bold text
/// - `[i]text[/i]` - Italic text
/// - `[u]text[/u]` - Underlined text
/// - `[l=Label Name]` - Label links (displays the label name)
/// - `[url=http://example.com]Link Text[/url]` - URL links (styled as blue underlined text)
/// - `[r12345]`, `[m123]`, `[a12345]` - Release/master/artist links by ID (skipped)
struct DiscogsFormatter {
    /// Parses Discogs formatting syntax and converts it to SwiftUI Text
    static func parse(_ text: String) -> Text {
        var result = AttributedString()
        var remaining = text[...]
        
        while !remaining.isEmpty {
            // Look for the next opening bracket
            if let bracketIndex = remaining.firstIndex(of: "[") {
                // Add text before the bracket
                let beforeBracket = remaining[..<bracketIndex]
                if !beforeBracket.isEmpty {
                    result.append(AttributedString(String(beforeBracket)))
                }
                
                // Find the closing bracket
                if let closingBracket = remaining[bracketIndex...].firstIndex(of: "]") {
                    let tagContent = remaining[bracketIndex...].index(after: bracketIndex)..<closingBracket
                    let tag = String(remaining[tagContent])
                    
                    // Handle different tag types
                    if tag.hasPrefix("a=") {
                        // Artist link: [a=Artist Name] -> just show the name
                        let artistName = String(tag.dropFirst(2))
                        result.append(AttributedString(artistName))
                        remaining = remaining[remaining.index(after: closingBracket)...]
                    } else if tag.hasPrefix("a") && tag.count > 1 && tag.dropFirst().allSatisfy(\.isNumber) {
                        // Artist link by ID: [a12345] -> skip (no way to resolve)
                        remaining = remaining[remaining.index(after: closingBracket)...]
                    } else if tag == "b" {
                        // Bold start: [b]...[/b]
                        if let endTag = findClosingTag(in: remaining[remaining.index(after: closingBracket)...], tag: "b") {
                            let boldText = String(remaining[remaining.index(after: closingBracket)..<endTag.startIndex])
                            var attributed = AttributedString(boldText)
                            attributed.inlinePresentationIntent = .stronglyEmphasized
                            result.append(attributed)
                            remaining = remaining[endTag.endIndex...]
                        } else {
                            // No closing tag found, skip the opening tag
                            remaining = remaining[remaining.index(after: closingBracket)...]
                        }
                    } else if tag == "/b" {
                        // Bold end (orphaned closing tag, skip it)
                        remaining = remaining[remaining.index(after: closingBracket)...]
                    } else if tag == "i" {
                        // Italic start: [i]...[/i]
                        if let endTag = findClosingTag(in: remaining[remaining.index(after: closingBracket)...], tag: "i") {
                            let italicText = String(remaining[remaining.index(after: closingBracket)..<endTag.startIndex])
                            var attributed = AttributedString(italicText)
                            attributed.inlinePresentationIntent = .emphasized
                            result.append(attributed)
                            remaining = remaining[endTag.endIndex...]
                        } else {
                            remaining = remaining[remaining.index(after: closingBracket)...]
                        }
                    } else if tag == "/i" {
                        // Italic end (orphaned closing tag, skip it)
                        remaining = remaining[remaining.index(after: closingBracket)...]
                    } else if tag == "u" {
                        // Underline start: [u]...[/u] (but not [url=)
                        if let endTag = findClosingTag(in: remaining[remaining.index(after: closingBracket)...], tag: "u") {
                            let underlineText = String(remaining[remaining.index(after: closingBracket)..<endTag.startIndex])
                            var attributed = AttributedString(underlineText)
                            attributed.underlineStyle = .single
                            result.append(attributed)
                            remaining = remaining[endTag.endIndex...]
                        } else {
                            remaining = remaining[remaining.index(after: closingBracket)...]
                        }
                    } else if tag == "/u" {
                        // Underline end (orphaned closing tag, skip it)
                        remaining = remaining[remaining.index(after: closingBracket)...]
                    } else if tag.hasPrefix("l=") {
                        // Label link: [l=Label Name] -> just show the name
                        let labelName = String(tag.dropFirst(2))
                        result.append(AttributedString(labelName))
                        remaining = remaining[remaining.index(after: closingBracket)...]
                    } else if tag.hasPrefix("url=") {
                        // URL link: [url=http://example.com]Link Text[/url]
                        let urlString = String(tag.dropFirst(4))
                        if let urlEndTag = findClosingTag(in: remaining[remaining.index(after: closingBracket)...], tag: "url") {
                            let linkText = String(remaining[remaining.index(after: closingBracket)..<urlEndTag.startIndex])
                            var attributed = AttributedString(linkText)
                            if let url = URL(string: urlString) {
                                attributed.link = url
                            }
                            attributed.foregroundColor = .blue
                            attributed.underlineStyle = .single
                            result.append(attributed)
                            remaining = remaining[urlEndTag.endIndex...]
                        } else {
                            // No closing tag, just show the URL
                            result.append(AttributedString(urlString))
                            remaining = remaining[remaining.index(after: closingBracket)...]
                        }
                    } else if tag.hasPrefix("r") && tag.count > 1 && tag.dropFirst().allSatisfy(\.isNumber) {
                        // Release link by ID: [r12345] -> skip (no way to resolve)
                        remaining = remaining[remaining.index(after: closingBracket)...]
                    } else if tag.hasPrefix("m") && tag.count > 1 && tag.dropFirst().allSatisfy(\.isNumber) {
                        // Master link by ID: [m123] -> skip (no way to resolve)
                        remaining = remaining[remaining.index(after: closingBracket)...]
                    } else {
                        // Unknown tag, skip it
                        remaining = remaining[remaining.index(after: closingBracket)...]
                    }
                } else {
                    // No closing bracket found, add rest as plain text
                    result.append(AttributedString(String(remaining)))
                    break
                }
            } else {
                // No more brackets, add remaining text
                result.append(AttributedString(String(remaining)))
                break
            }
        }
        
        return Text(result)
    }
    
    /// Finds a closing tag like [/tag] in the remaining text, handling nested tags
    private static func findClosingTag(in text: Substring, tag: String) -> (startIndex: String.Index, endIndex: String.Index)? {
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
                // Found another opening tag of the same type, increase depth
                depth += 1
            } else if currentTag == "/\(tag)" {
                // Found a closing tag, decrease depth
                depth -= 1
                if depth == 0 {
                    // Found the matching closing tag
                    return (openBracket, text.index(after: closeBracket))
                }
            }
            
            searchStart = text.index(after: closeBracket)
        }
        
        return nil
    }
}
