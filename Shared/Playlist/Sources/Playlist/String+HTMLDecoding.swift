//
//  String+HTMLDecoding.swift
//  Playlist
//
//  Decodes HTML entities in strings from API responses.
//

import Foundation

extension String {
    /// Decodes HTML entities in the string.
    ///
    /// Handles:
    /// - Numeric character references: `&#324;` (decimal) and `&#x144;` (hexadecimal)
    /// - Named entities: `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&nbsp;`
    ///
    /// - Returns: The string with HTML entities decoded, or the original string if no entities found.
    var htmlDecoded: String {
        guard contains("&") else { return self }
        
        var result = self
        
        // Decode numeric character references (decimal): &#324;
        result = result.replacingNumericEntities()
        
        // Decode numeric character references (hexadecimal): &#x144;
        result = result.replacingHexEntities()
        
        // Decode common named entities
        result = result.replacingNamedEntities()
        
        return result
    }
    
    private func replacingNumericEntities() -> String {
        var result = self
        let pattern = "&#(\\d+);"
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return result
        }
        
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        
        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let codePointRange = Range(match.range(at: 1), in: result),
                  let codePoint = UInt32(result[codePointRange]),
                  let scalar = Unicode.Scalar(codePoint) else {
                continue
            }
            
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        
        return result
    }
    
    private func replacingHexEntities() -> String {
        var result = self
        let pattern = "&#[xX]([0-9a-fA-F]+);"
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return result
        }
        
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        
        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let hexRange = Range(match.range(at: 1), in: result),
                  let codePoint = UInt32(result[hexRange], radix: 16),
                  let scalar = Unicode.Scalar(codePoint) else {
                continue
            }
            
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        
        return result
    }
    
    private func replacingNamedEntities() -> String {
        var result = self
        
        // Common HTML named entities
        let namedEntities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&nbsp;", "\u{00A0}"),
            ("&rsquo;", "'"),
            ("&lsquo;", "'"),
            ("&rdquo;", "\u{201D}"),
            ("&ldquo;", "\u{201C}"),
            ("&ndash;", "–"),
            ("&mdash;", "—"),
            ("&hellip;", "…"),
        ]
        
        for (entity, replacement) in namedEntities {
            result = result.replacing(entity, with: replacement)
        }
        
        return result
    }
}
