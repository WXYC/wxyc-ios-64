/*
 DiscogsFormatterTests.swift
 
 Comprehensive unit tests for DiscogsFormatter
 
 Test Coverage:
 - Artist links: [a=Name] and [a12345]
 - Bold formatting: [b]...[/b]
 - Italic formatting: [i]...[/i]
 - Underline formatting: [u]...[/u]
 - Label links: [l=Name]
 - URL links: [url=...]...[/url]
 - Release/Master links: [r12345], [m123]
 - Orphaned closing tags
 - Edge cases and error handling
 */

import Testing
import Foundation
import SwiftUI
@testable import WXYC

// MARK: - Mock Entity Resolver

/// Mock resolver for testing async entity resolution
struct MockDiscogsEntityResolver: DiscogsEntityResolver {
    var artists: [Int: String] = [:]
    var releases: [Int: String] = [:]
    var masters: [Int: String] = [:]
    var shouldThrowError: Bool = false
    
    func resolveArtist(id: Int) async throws -> String {
        if shouldThrowError {
            throw MockError.resolutionFailed
        }
        guard let name = artists[id] else {
            throw MockError.notFound
        }
        return name
    }
    
    func resolveRelease(id: Int) async throws -> String {
        if shouldThrowError {
            throw MockError.resolutionFailed
        }
        guard let name = releases[id] else {
            throw MockError.notFound
        }
        return name
    }
    
    func resolveMaster(id: Int) async throws -> String {
        if shouldThrowError {
            throw MockError.resolutionFailed
        }
        guard let name = masters[id] else {
            throw MockError.notFound
        }
        return name
    }
    
    enum MockError: Error {
        case notFound
        case resolutionFailed
    }
}

// MARK: - Artist Tag Tests

@Suite("Artist Tag Tests")
struct ArtistTagTests {
    
    @Test("Parses artist link with name")
    func parsesArtistLinkWithName() {
        // Given
        let input = "[a=The Beatles]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "The Beatles")
    }
    
    @Test("Parses artist link with special characters")
    func parsesArtistLinkWithSpecialCharacters() {
        // Given
        let input = "[a=Guns N' Roses]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "Guns N' Roses")
    }
    
    @Test("Skips artist link by ID")
    func skipsArtistLinkById() {
        // Given
        let input = "[a12345]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "")
    }
    
    @Test("Skips artist link with large ID")
    func skipsArtistLinkWithLargeId() {
        // Given
        let input = "[a9999999]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "")
    }
    
    @Test("Preserves text around artist ID link")
    func preservesTextAroundArtistIdLink() {
        // Given
        let input = "See [a12345] for more"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "See  for more")
    }
}

// MARK: - Bold Tag Tests

@Suite("Bold Tag Tests")
struct BoldTagTests {
    
    @Test("Parses bold text")
    func parsesBoldText() {
        // Given
        let input = "[b]bold text[/b]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "bold text")
        
        // Verify bold attribute
        let range = result.startIndex..<result.endIndex
        let intent = result[range].inlinePresentationIntent
        #expect(intent == .stronglyEmphasized)
    }
    
    @Test("Parses bold text with surrounding content")
    func parsesBoldWithSurroundingContent() {
        // Given
        let input = "This is [b]bold[/b] text"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "This is bold text")
    }
    
    @Test("Skips orphaned bold closing tag")
    func skipsOrphanedBoldClosingTag() {
        // Given
        let input = "text [/b] more"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "text  more")
    }
    
    @Test("Handles unclosed bold tag")
    func handlesUnclosedBoldTag() {
        // Given
        let input = "[b]no closing tag"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "no closing tag")
    }
    
    @Test("Handles empty bold content")
    func handlesEmptyBoldContent() {
        // Given
        let input = "[b][/b]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "")
    }
}

// MARK: - Italic Tag Tests

@Suite("Italic Tag Tests")
struct ItalicTagTests {
    
    @Test("Parses italic text")
    func parsesItalicText() {
        // Given
        let input = "[i]italic text[/i]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "italic text")
        
        // Verify italic attribute
        let range = result.startIndex..<result.endIndex
        let intent = result[range].inlinePresentationIntent
        #expect(intent == .emphasized)
    }
    
    @Test("Parses italic text with surrounding content")
    func parsesItalicWithSurroundingContent() {
        // Given
        let input = "This is [i]italic[/i] text"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "This is italic text")
    }
    
    @Test("Skips orphaned italic closing tag")
    func skipsOrphanedItalicClosingTag() {
        // Given
        let input = "text [/i] more"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "text  more")
    }
    
    @Test("Handles unclosed italic tag")
    func handlesUnclosedItalicTag() {
        // Given
        let input = "[i]no closing tag"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "no closing tag")
    }
}

// MARK: - Underline Tag Tests

@Suite("Underline Tag Tests")
struct UnderlineTagTests {
    
    @Test("Parses underlined text")
    func parsesUnderlinedText() {
        // Given
        let input = "[u]underlined text[/u]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "underlined text")
        
        // Verify underline attribute
        let range = result.startIndex..<result.endIndex
        let style = result[range].underlineStyle
        #expect(style == .single)
    }
    
    @Test("Parses underline text with surrounding content")
    func parsesUnderlineWithSurroundingContent() {
        // Given
        let input = "This is [u]underlined[/u] text"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "This is underlined text")
    }
    
    @Test("Skips orphaned underline closing tag")
    func skipsOrphanedUnderlineClosingTag() {
        // Given
        let input = "text [/u] more"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "text  more")
    }
    
    @Test("Handles unclosed underline tag")
    func handlesUnclosedUnderlineTag() {
        // Given
        let input = "[u]no closing tag"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "no closing tag")
    }
}

// MARK: - Label Tag Tests

@Suite("Label Tag Tests")
struct LabelTagTests {
    
    @Test("Parses label link")
    func parsesLabelLink() {
        // Given
        let input = "[l=Blue Note Records]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "Blue Note Records")
    }
    
    @Test("Parses label link with special characters")
    func parsesLabelLinkWithSpecialCharacters() {
        // Given
        let input = "[l=4AD]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "4AD")
    }
    
    @Test("Parses label link with surrounding text")
    func parsesLabelLinkWithSurroundingText() {
        // Given
        let input = "Released on [l=Motown] in 1965"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "Released on Motown in 1965")
    }
}

// MARK: - URL Tag Tests

@Suite("URL Tag Tests")
struct URLTagTests {
    
    @Test("Parses URL link")
    func parsesURLLink() {
        // Given
        let input = "[url=https://example.com]Click here[/url]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "Click here")
        
        // Verify link attribute
        let range = result.startIndex..<result.endIndex
        let link = result[range].link
        #expect(link == URL(string: "https://example.com"))
    }
    
    @Test("Parses URL link with underline style")
    func parsesURLLinkWithUnderlineStyle() {
        // Given
        let input = "[url=https://example.com]Link[/url]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        let range = result.startIndex..<result.endIndex
        let style = result[range].underlineStyle
        #expect(style == .single)
    }
    
    @Test("Parses URL link with secondary color")
    func parsesURLLinkWithSecondaryColor() {
        // Given
        let input = "[url=https://example.com]Link[/url]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        let range = result.startIndex..<result.endIndex
        let color = result[range].foregroundColor
        #expect(color == .secondary)
    }
    
    @Test("Handles URL without closing tag - shows URL")
    func handlesURLWithoutClosingTag() {
        // Given
        let input = "[url=https://example.com]orphaned"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "https://example.comorphaned")
    }
    
    @Test("Handles invalid URL gracefully")
    func handlesInvalidURLGracefully() {
        // Given - URL with spaces is invalid
        let input = "[url=not a valid url]text[/url]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then - Should still show text, just without link attribute
        #expect(String(result.characters) == "text")
    }
    
    @Test("Parses URL with complex query string")
    func parsesURLWithComplexQueryString() {
        // Given
        let input = "[url=https://example.com/path?query=value&other=123]Link[/url]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "Link")
        let range = result.startIndex..<result.endIndex
        let link = result[range].link
        #expect(link == URL(string: "https://example.com/path?query=value&other=123"))
    }
}

// MARK: - ID-based Tag Tests

@Suite("ID-based Tag Tests")
struct IDTagTests {
    
    @Test("Skips release link by ID")
    func skipsReleaseLinkById() {
        // Given
        let input = "[r12345]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "")
    }
    
    @Test("Skips master link by ID")
    func skipsMasterLinkById() {
        // Given
        let input = "[m123]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "")
    }
    
    @Test("Preserves text around release ID")
    func preservesTextAroundReleaseId() {
        // Given
        let input = "See release [r99999] for details"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "See release  for details")
    }
    
    @Test("Preserves text around master ID")
    func preservesTextAroundMasterId() {
        // Given
        let input = "Master [m456] version"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "Master  version")
    }
}

// MARK: - Edge Cases

@Suite("Edge Cases")
struct EdgeCaseTests {
    
    @Test("Handles plain text without tags")
    func handlesPlainText() {
        // Given
        let input = "Just plain text with no formatting"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "Just plain text with no formatting")
    }
    
    @Test("Handles empty string")
    func handlesEmptyString() {
        // Given
        let input = ""
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "")
    }
    
    @Test("Handles multiple consecutive tags")
    func handlesMultipleConsecutiveTags() {
        // Given
        let input = "[a=Artist A][a=Artist B][a=Artist C]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "Artist AArtist BArtist C")
    }
    
    @Test("Handles mixed tags and text")
    func handlesMixedTagsAndText() {
        // Given
        let input = "Check out [a=The Beatles] on [l=Apple Records]!"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "Check out The Beatles on Apple Records!")
    }
    
    @Test("Handles nested formatting tags")
    func handlesNestedFormattingTags() {
        // Given - Bold containing italic
        // Note: The parser applies bold to the entire content but does not recursively
        // parse nested tags within styled content - they appear as literal text
        let input = "[b]bold [i]and italic[/i][/b]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then - Inner tags appear literally within the bold text
        #expect(String(result.characters) == "bold [i]and italic[/i]")
    }
    
    @Test("Handles unclosed bracket")
    func handlesUnclosedBracket() {
        // Given
        let input = "Text with [unclosed bracket"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then - Parser adds text before bracket, then adds full remaining when no ] found
        // This results in duplication (known parser behavior)
        #expect(String(result.characters) == "Text with Text with [unclosed bracket")
    }
    
    @Test("Handles unknown tags")
    func handlesUnknownTags() {
        // Given
        let input = "[unknown]text[/unknown]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then - Both [unknown] and [/unknown] are unknown tags and get skipped
        #expect(String(result.characters) == "text")
    }
    
    @Test("Handles real-world Discogs text")
    func handlesRealWorldDiscogsText() {
        // Given - Example from Discogs
        let input = "Written by [a=John Lennon] and [a=Paul McCartney]. Released on [l=Apple Records] in 1969. See [r123456] for more info."
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "Written by John Lennon and Paul McCartney. Released on Apple Records in 1969. See  for more info.")
    }
    
    @Test("Handles text with only brackets")
    func handlesTextWithOnlyBrackets() {
        // Given
        let input = "[]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then - Empty tag content, unknown tag type
        #expect(String(result.characters) == "")
    }
    
    @Test("Handles deeply nested same-type tags")
    func handlesDeeplyNestedSameTypeTags() {
        // Given - The parser handles depth for finding the matching closing tag
        // but does not recursively parse the content within styled regions
        let input = "[b]outer [b]inner[/b] outer[/b]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then - Inner tags appear literally within the bold text
        #expect(String(result.characters) == "outer [b]inner[/b] outer")
    }
    
    @Test("Handles multiple different formatting in sequence")
    func handlesMultipleFormattingInSequence() {
        // Given
        let input = "[b]bold[/b] then [i]italic[/i] then [u]underline[/u]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "bold then italic then underline")
    }
    
    @Test("Does not confuse url tag with u tag")
    func doesNotConfuseUrlWithU() {
        // Given - [url=...] should not be confused with [u]
        let input = "[url=https://example.com]link[/url]"
        
        // When
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        // Then
        #expect(String(result.characters) == "link")
        let range = result.startIndex..<result.endIndex
        let link = result[range].link
        #expect(link != nil)
    }
}

// MARK: - Attribute Verification Tests

@Suite("Attribute Verification")
struct AttributeVerificationTests {
    
    @Test("Bold text has correct presentation intent")
    func boldHasCorrectIntent() {
        let result = DiscogsFormatter.parseToAttributedString("[b]text[/b]")
        
        var foundBold = false
        for run in result.runs {
            if run.inlinePresentationIntent == .stronglyEmphasized {
                foundBold = true
                break
            }
        }
        #expect(foundBold)
    }
    
    @Test("Italic text has correct presentation intent")
    func italicHasCorrectIntent() {
        let result = DiscogsFormatter.parseToAttributedString("[i]text[/i]")
        
        var foundItalic = false
        for run in result.runs {
            if run.inlinePresentationIntent == .emphasized {
                foundItalic = true
                break
            }
        }
        #expect(foundItalic)
    }
    
    @Test("Underlined text has correct style")
    func underlineHasCorrectStyle() {
        let result = DiscogsFormatter.parseToAttributedString("[u]text[/u]")
        
        var foundUnderline = false
        for run in result.runs {
            if run.underlineStyle == .single {
                foundUnderline = true
                break
            }
        }
        #expect(foundUnderline)
    }
    
    @Test("URL has all required attributes")
    func urlHasAllRequiredAttributes() {
        let result = DiscogsFormatter.parseToAttributedString("[url=https://test.com]link[/url]")
        
        var hasLink = false
        var hasSecondaryColor = false
        var hasUnderline = false
        
        for run in result.runs {
            if run.link != nil {
                hasLink = true
            }
            if run.foregroundColor == .secondary {
                hasSecondaryColor = true
            }
            if run.underlineStyle == .single {
                hasUnderline = true
            }
        }
        
        #expect(hasLink)
        #expect(hasSecondaryColor)
        #expect(hasUnderline)
    }
    
    @Test("Plain text has no special attributes")
    func plainTextHasNoSpecialAttributes() {
        let result = DiscogsFormatter.parseToAttributedString("plain text")
        
        for run in result.runs {
            #expect(run.inlinePresentationIntent == nil)
            #expect(run.underlineStyle == nil)
            #expect(run.link == nil)
        }
    }
}

// MARK: - Async Entity Resolution Tests

@Suite("Entity Resolution Tests")
struct EntityResolutionTests {
    
    @Test("Resolves artist ID to name with link, stripping disambiguation suffix")
    func resolvesArtistIdToName() async {
        // Given
        let input = "[a8390436]"
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[8390436] = "Salamanda (8)"  // Discogs adds " (8)" for disambiguation
        
        // When
        let result = await DiscogsFormatter.parseToAttributedString(input, resolver: resolver)
        
        // Then - disambiguation suffix should be stripped
        #expect(String(result.characters) == "Salamanda")
        
        // Verify link attribute
        let range = result.startIndex..<result.endIndex
        #expect(result[range].link == URL(string: "https://www.discogs.com/artist/8390436"))
        #expect(result[range].foregroundColor == .secondary)
        #expect(result[range].underlineStyle == .single)
    }
    
    @Test("Resolves multiple artist IDs")
    func resolvesMultipleArtistIds() async {
        // Given
        let input = "Featuring [a123] and [a456]"
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[123] = "Artist One"
        resolver.artists[456] = "Artist Two"
        
        // When
        let result = await DiscogsFormatter.parseToAttributedString(input, resolver: resolver)
        
        // Then
        #expect(String(result.characters) == "Featuring Artist One and Artist Two")
    }
    
    @Test("Resolves release ID to title with link")
    func resolvesReleaseIdToTitle() async {
        // Given
        let input = "[r99999]"
        var resolver = MockDiscogsEntityResolver()
        resolver.releases[99999] = "Abbey Road"
        
        // When
        let result = await DiscogsFormatter.parseToAttributedString(input, resolver: resolver)
        
        // Then
        #expect(String(result.characters) == "Abbey Road")
        
        // Verify link attribute
        let range = result.startIndex..<result.endIndex
        #expect(result[range].link == URL(string: "https://www.discogs.com/release/99999"))
    }
    
    @Test("Resolves master ID to title with link")
    func resolvesMasterIdToTitle() async {
        // Given
        let input = "[m12345]"
        var resolver = MockDiscogsEntityResolver()
        resolver.masters[12345] = "Kind of Blue"
        
        // When
        let result = await DiscogsFormatter.parseToAttributedString(input, resolver: resolver)
        
        // Then
        #expect(String(result.characters) == "Kind of Blue")
        
        // Verify link attribute
        let range = result.startIndex..<result.endIndex
        #expect(result[range].link == URL(string: "https://www.discogs.com/master/12345"))
    }
    
    @Test("Handles mixed resolved and named tags")
    func handlesMixedResolvedAndNamedTags() async {
        // Given
        let input = "[a=John Lennon] collaborated with [a999]"
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[999] = "Yoko Ono"
        
        // When
        let result = await DiscogsFormatter.parseToAttributedString(input, resolver: resolver)
        
        // Then
        #expect(String(result.characters) == "John Lennon collaborated with Yoko Ono")
    }
    
    @Test("Skips unresolvable IDs gracefully")
    func skipsUnresolvableIds() async {
        // Given - ID not in resolver
        let input = "See [a99999999] for more"
        let resolver = MockDiscogsEntityResolver() // Empty, no mappings
        
        // When
        let result = await DiscogsFormatter.parseToAttributedString(input, resolver: resolver)
        
        // Then - Unresolved ID is skipped (empty)
        #expect(String(result.characters) == "See  for more")
    }
    
    @Test("Handles resolver errors gracefully")
    func handlesResolverErrors() async {
        // Given
        let input = "[a123] was great"
        var resolver = MockDiscogsEntityResolver()
        resolver.shouldThrowError = true
        
        // When
        let result = await DiscogsFormatter.parseToAttributedString(input, resolver: resolver)
        
        // Then - Failed resolution is skipped
        #expect(String(result.characters) == " was great")
    }
    
    @Test("Resolves complex real-world text")
    func resolvesComplexRealWorldText() async {
        // Given
        let input = "Written by [a=John Lennon] and [a=Paul McCartney]. Produced by [a5678]. See release [r12345] for credits."
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[5678] = "George Martin"
        resolver.releases[12345] = "Sgt. Pepper's"
        
        // When
        let result = await DiscogsFormatter.parseToAttributedString(input, resolver: resolver)
        
        // Then
        #expect(String(result.characters) == "Written by John Lennon and Paul McCartney. Produced by George Martin. See release Sgt. Pepper's for credits.")
    }
    
    @Test("Preserves formatting with resolved IDs")
    func preservesFormattingWithResolvedIds() async {
        // Given
        let input = "[b]Bold[/b] by [a100]"
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[100] = "Test Artist"
        
        // When
        let result = await DiscogsFormatter.parseToAttributedString(input, resolver: resolver)
        
        // Then
        #expect(String(result.characters) == "Bold by Test Artist")
        
        // Verify bold is preserved
        var foundBold = false
        for run in result.runs {
            if run.inlinePresentationIntent == .stronglyEmphasized {
                foundBold = true
                break
            }
        }
        #expect(foundBold)
    }
    
    @Test("Resolves all entity types in one text")
    func resolvesAllEntityTypes() async {
        // Given
        let input = "Artist [a1], Release [r2], Master [m3]"
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[1] = "The Artist"
        resolver.releases[2] = "The Album"
        resolver.masters[3] = "The Master"
        
        // When
        let result = await DiscogsFormatter.parseToAttributedString(input, resolver: resolver)
        
        // Then
        #expect(String(result.characters) == "Artist The Artist, Release The Album, Master The Master")
    }
    
    @Test("Strips disambiguation suffix from artist names")
    func stripsDisambiguationSuffix() async {
        // Given - various disambiguation formats
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[1] = "Prince (2)"           // Single digit
        resolver.artists[2] = "Nirvana (123)"        // Multiple digits
        resolver.artists[3] = "The Beatles"          // No suffix
        resolver.artists[4] = "Blink-182"            // Number in name (not suffix)
        resolver.artists[5] = "Level 42"             // Number in name (not suffix)
        resolver.artists[6] = "Test (Band)"          // Parentheses but not number
        
        // When/Then
        let result1 = await DiscogsFormatter.parseToAttributedString("[a1]", resolver: resolver)
        #expect(String(result1.characters) == "Prince")
        
        let result2 = await DiscogsFormatter.parseToAttributedString("[a2]", resolver: resolver)
        #expect(String(result2.characters) == "Nirvana")
        
        let result3 = await DiscogsFormatter.parseToAttributedString("[a3]", resolver: resolver)
        #expect(String(result3.characters) == "The Beatles")
        
        let result4 = await DiscogsFormatter.parseToAttributedString("[a4]", resolver: resolver)
        #expect(String(result4.characters) == "Blink-182")
        
        let result5 = await DiscogsFormatter.parseToAttributedString("[a5]", resolver: resolver)
        #expect(String(result5.characters) == "Level 42")
        
        let result6 = await DiscogsFormatter.parseToAttributedString("[a6]", resolver: resolver)
        #expect(String(result6.characters) == "Test (Band)")
    }
    
    @Test("Does not strip suffix from release or master names")
    func doesNotStripSuffixFromNonArtists() async {
        // Given - releases and masters may have valid "(N)" in titles
        var resolver = MockDiscogsEntityResolver()
        resolver.releases[1] = "Album Title (2)"
        resolver.masters[1] = "Master Title (Remastered) (3)"
        
        // When
        let result1 = await DiscogsFormatter.parseToAttributedString("[r1]", resolver: resolver)
        let result2 = await DiscogsFormatter.parseToAttributedString("[m1]", resolver: resolver)
        
        // Then - suffix should be preserved for non-artists
        #expect(String(result1.characters) == "Album Title (2)")
        #expect(String(result2.characters) == "Master Title (Remastered) (3)")
    }
}

