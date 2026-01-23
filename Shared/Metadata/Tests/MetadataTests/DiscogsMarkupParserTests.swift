//
//  DiscogsMarkupParserTests.swift
//  Metadata
//
//  Unit tests for DiscogsMarkupParser
//
//  Test Coverage:
//  - Artist links: [a=Name] and [a12345]
//  - Bold formatting: [b]...[/b]
//  - Italic formatting: [i]...[/i]
//  - Underline formatting: [u]...[/u]
//  - Label links: [l=Name]
//  - URL links: [url=...]...[/url]
//  - Release/Master links: [r12345], [r=12345], [m123], [m=123]
//  - Orphaned closing tags
//  - Edge cases and error handling
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//
    
import Testing
import Foundation
@testable import Metadata

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
        let input = "[a=The Beatles]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "The Beatles")
    }

    @Test("Parses artist link with special characters")
    func parsesArtistLinkWithSpecialCharacters() {
        let input = "[a=Guns N' Roses]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "Guns N' Roses")
    }
    
    @Test("Skips artist link by ID in sync mode")
    func skipsArtistLinkById() {
        let input = "[a12345]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "")
    }
    
    @Test("Skips artist link with large ID")
    func skipsArtistLinkWithLargeId() {
        let input = "[a9999999]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "")
    }
    
    @Test("Preserves text around artist ID link")
    func preservesTextAroundArtistIdLink() {
        let input = "See [a12345] for more"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "See  for more")
    }
    
    @Test("Artist link has correct URL")
    func artistLinkHasCorrectUrl() {
        let input = "[a=Test Artist]"
        let result = DiscogsMarkupParser.parse(input)
        
        let range = result.startIndex..<result.endIndex
        let link = result[range].link
        #expect(link?.absoluteString.contains("discogs.com/search") == true)
        #expect(link?.absoluteString.contains("type=artist") == true)
    }
}

// MARK: - Bold Tag Tests

@Suite("Bold Tag Tests")
struct BoldTagTests {
    
    @Test("Parses bold text")
    func parsesBoldText() {
        let input = "[b]bold text[/b]"
        let result = DiscogsMarkupParser.parse(input)

        #expect(String(result.characters) == "bold text")

        let range = result.startIndex..<result.endIndex
        let intent = result[range].inlinePresentationIntent
        #expect(intent == .stronglyEmphasized)
    }
    
    @Test("Parses bold text with surrounding content")
    func parsesBoldWithSurroundingContent() {
        let input = "This is [b]bold[/b] text"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "This is bold text")
    }
    
    @Test("Skips orphaned bold closing tag")
    func skipsOrphanedBoldClosingTag() {
        let input = "text [/b] more"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "text  more")
    }
    
    @Test("Handles unclosed bold tag")
    func handlesUnclosedBoldTag() {
        let input = "[b]no closing tag"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "no closing tag")
    }
    
    @Test("Handles empty bold content")
    func handlesEmptyBoldContent() {
        let input = "[b][/b]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "")
    }
}

// MARK: - Italic Tag Tests
    
@Suite("Italic Tag Tests")
struct ItalicTagTests {
    
    @Test("Parses italic text")
    func parsesItalicText() {
        let input = "[i]italic text[/i]"
        let result = DiscogsMarkupParser.parse(input)

        #expect(String(result.characters) == "italic text")

        let range = result.startIndex..<result.endIndex
        let intent = result[range].inlinePresentationIntent
        #expect(intent == .emphasized)
    }
    
    @Test("Parses italic text with surrounding content")
    func parsesItalicWithSurroundingContent() {
        let input = "This is [i]italic[/i] text"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "This is italic text")
    }
    
    @Test("Skips orphaned italic closing tag")
    func skipsOrphanedItalicClosingTag() {
        let input = "text [/i] more"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "text  more")
    }
    
    @Test("Handles unclosed italic tag")
    func handlesUnclosedItalicTag() {
        let input = "[i]no closing tag"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "no closing tag")
    }
}

// MARK: - Underline Tag Tests
    
@Suite("Underline Tag Tests")
struct UnderlineTagTests {
    
    @Test("Parses underlined text")
    func parsesUnderlinedText() {
        let input = "[u]underlined text[/u]"
        let result = DiscogsMarkupParser.parse(input)

        #expect(String(result.characters) == "underlined text")

        let range = result.startIndex..<result.endIndex
        let style = result[range].underlineStyle
        #expect(style == .single)
    }
    
    @Test("Parses underline text with surrounding content")
    func parsesUnderlineWithSurroundingContent() {
        let input = "This is [u]underlined[/u] text"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "This is underlined text")
    }
    
    @Test("Skips orphaned underline closing tag")
    func skipsOrphanedUnderlineClosingTag() {
        let input = "text [/u] more"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "text  more")
    }
    
    @Test("Handles unclosed underline tag")
    func handlesUnclosedUnderlineTag() {
        let input = "[u]no closing tag"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "no closing tag")
    }
}

// MARK: - Label Tag Tests
    
@Suite("Label Tag Tests")
struct LabelTagTests {
    
    @Test("Parses label link")
    func parsesLabelLink() {
        let input = "[l=Blue Note Records]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "Blue Note Records")
    }

    @Test("Parses label link with special characters")
    func parsesLabelLinkWithSpecialCharacters() {
        let input = "[l=4AD]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "4AD")
    }
    
    @Test("Parses label link with surrounding text")
    func parsesLabelLinkWithSurroundingText() {
        let input = "Released on [l=Motown] in 1965"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "Released on Motown in 1965")
    }
}

// MARK: - URL Tag Tests
    
@Suite("URL Tag Tests")
struct URLTagTests {
    
    @Test("Parses URL link")
    func parsesURLLink() {
        let input = "[url=https://example.com]Click here[/url]"
        let result = DiscogsMarkupParser.parse(input)

        #expect(String(result.characters) == "Click here")

        let range = result.startIndex..<result.endIndex
        let link = result[range].link
        #expect(link == URL(string: "https://example.com"))
    }
    
    @Test("Parses URL link with underline style")
    func parsesURLLinkWithUnderlineStyle() {
        let input = "[url=https://example.com]Link[/url]"
        let result = DiscogsMarkupParser.parse(input)
        
        let range = result.startIndex..<result.endIndex
        let style = result[range].underlineStyle
        #expect(style == .single)
    }
    
    @Test("Handles URL without closing tag - shows URL")
    func handlesURLWithoutClosingTag() {
        let input = "[url=https://example.com]orphaned"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "https://example.comorphaned")
    }
    
    @Test("Handles invalid URL gracefully")
    func handlesInvalidURLGracefully() {
        let input = "[url=not a valid url]text[/url]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "text")
    }
    
    @Test("Parses URL with complex query string")
    func parsesURLWithComplexQueryString() {
        let input = "[url=https://example.com/path?query=value&other=123]Link[/url]"
        let result = DiscogsMarkupParser.parse(input)
        
        #expect(String(result.characters) == "Link")
        let range = result.startIndex..<result.endIndex
        let link = result[range].link
        #expect(link == URL(string: "https://example.com/path?query=value&other=123"))
    }
}

// MARK: - ID-based Tag Tests

@Suite("ID-based Tag Tests")
struct IDTagTests {
    
    @Test("Skips release link by ID in sync mode")
    func skipsReleaseLinkById() {
        let input = "[r12345]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "")
    }

    @Test("Skips master link by ID in sync mode")
    func skipsMasterLinkById() {
        let input = "[m123]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "")
    }
    
    @Test("Skips release link by ID with equals sign in sync mode")
    func skipsReleaseLinkByIdWithEquals() {
        let input = "[r=621811]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "")
    }
    
    @Test("Skips master link by ID with equals sign in sync mode")
    func skipsMasterLinkByIdWithEquals() {
        let input = "[m=199386]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "")
    }

    @Test("Preserves text around release ID")
    func preservesTextAroundReleaseId() {
        let input = "See release [r99999] for details"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "See release  for details")
    }

    @Test("Preserves text around master ID")
    func preservesTextAroundMasterId() {
        let input = "Master [m456] version"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "Master  version")
    }
}

// MARK: - Edge Cases
    
@Suite("Edge Cases")
struct EdgeCaseTests {
    
    @Test("Handles plain text without tags")
    func handlesPlainText() {
        let input = "Just plain text with no formatting"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "Just plain text with no formatting")
    }
    
    @Test("Handles empty string")
    func handlesEmptyString() {
        let input = ""
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "")
    }
    
    @Test("Handles multiple consecutive tags")
    func handlesMultipleConsecutiveTags() {
        let input = "[a=Artist A][a=Artist B][a=Artist C]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "Artist AArtist BArtist C")
    }
    
    @Test("Handles mixed tags and text")
    func handlesMixedTagsAndText() {
        let input = "Check out [a=The Beatles] on [l=Apple Records]!"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "Check out The Beatles on Apple Records!")
    }
    
    @Test("Handles nested formatting tags")
    func handlesNestedFormattingTags() {
        let input = "[b]bold [i]and italic[/i][/b]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "bold [i]and italic[/i]")
    }
    
    @Test("Handles unclosed bracket")
    func handlesUnclosedBracket() {
        let input = "Text with [unclosed bracket"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "Text with Text with [unclosed bracket")
    }
    
    @Test("Handles unknown tags")
    func handlesUnknownTags() {
        let input = "[unknown]text[/unknown]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "text")
    }
    
    @Test("Handles real-world Discogs text")
    func handlesRealWorldDiscogsText() {
        let input = "Written by [a=John Lennon] and [a=Paul McCartney]. Released on [l=Apple Records] in 1969. See [r123456] for more info."
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "Written by John Lennon and Paul McCartney. Released on Apple Records in 1969. See  for more info.")
    }
    
    @Test("Handles text with only brackets")
    func handlesTextWithOnlyBrackets() {
        let input = "[]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "")
    }
    
    @Test("Handles deeply nested same-type tags")
    func handlesDeeplyNestedSameTypeTags() {
        let input = "[b]outer [b]inner[/b] outer[/b]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "outer [b]inner[/b] outer")
    }
    
    @Test("Handles multiple different formatting in sequence")
    func handlesMultipleFormattingInSequence() {
        let input = "[b]bold[/b] then [i]italic[/i] then [u]underline[/u]"
        let result = DiscogsMarkupParser.parse(input)
        #expect(String(result.characters) == "bold then italic then underline")
    }

    @Test("Does not confuse url tag with u tag")
    func doesNotConfuseUrlWithU() {
        let input = "[url=https://example.com]link[/url]"
        let result = DiscogsMarkupParser.parse(input)
        
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
        let result = DiscogsMarkupParser.parse("[b]text[/b]")
        
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
        let result = DiscogsMarkupParser.parse("[i]text[/i]")
        
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
        let result = DiscogsMarkupParser.parse("[u]text[/u]")
        
        var foundUnderline = false
        for run in result.runs {
            if run.underlineStyle == .single {
                foundUnderline = true
                break
            }
        }
        #expect(foundUnderline)
    }
        
    @Test("URL has link and underline attributes")
    func urlHasLinkAndUnderline() {
        let result = DiscogsMarkupParser.parse("[url=https://test.com]link[/url]")
        
        var hasLink = false
        var hasUnderline = false
    
        for run in result.runs {
            if run.link != nil {
                hasLink = true
            }
            if run.underlineStyle == .single {
                hasUnderline = true
            }
        }
        
        #expect(hasLink)
        #expect(hasUnderline)
    }
    
    @Test("Plain text has no special attributes")
    func plainTextHasNoSpecialAttributes() {
        let result = DiscogsMarkupParser.parse("plain text")
    
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
        let input = "[a8390436]"
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[8390436] = "Salamanda (8)"
        
        let result = await DiscogsMarkupParser.parse(input, resolver: resolver)
        
        #expect(String(result.characters) == "Salamanda")
    
        let range = result.startIndex..<result.endIndex
        #expect(result[range].link == URL(string: "https://www.discogs.com/artist/8390436"))
        #expect(result[range].underlineStyle == .single)
    }
    
    @Test("Resolves multiple artist IDs")
    func resolvesMultipleArtistIds() async {
        let input = "Featuring [a123] and [a456]"
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[123] = "Artist One"
        resolver.artists[456] = "Artist Two"
        
        let result = await DiscogsMarkupParser.parse(input, resolver: resolver)
    
        #expect(String(result.characters) == "Featuring Artist One and Artist Two")
    }
    
    @Test("Resolves release ID to title with link")
    func resolvesReleaseIdToTitle() async {
        let input = "[r99999]"
        var resolver = MockDiscogsEntityResolver()
        resolver.releases[99999] = "Abbey Road"
        
        let result = await DiscogsMarkupParser.parse(input, resolver: resolver)
        
        #expect(String(result.characters) == "Abbey Road")
    
        let range = result.startIndex..<result.endIndex
        #expect(result[range].link == URL(string: "https://www.discogs.com/release/99999"))
    }
    
    @Test("Resolves master ID to title with link")
    func resolvesMasterIdToTitle() async {
        let input = "[m12345]"
        var resolver = MockDiscogsEntityResolver()
        resolver.masters[12345] = "Kind of Blue"
        
        let result = await DiscogsMarkupParser.parse(input, resolver: resolver)
    
        #expect(String(result.characters) == "Kind of Blue")

        let range = result.startIndex..<result.endIndex
        #expect(result[range].link == URL(string: "https://www.discogs.com/master/12345"))
    }

    @Test("Resolves release ID with equals sign to title with link")
    func resolvesReleaseIdWithEqualsToTitle() async {
        let input = "[r=621811]"
        var resolver = MockDiscogsEntityResolver()
        resolver.releases[621811] = "The Cover Up"

        let result = await DiscogsMarkupParser.parse(input, resolver: resolver)

        #expect(String(result.characters) == "The Cover Up")

        let range = result.startIndex..<result.endIndex
        #expect(result[range].link == URL(string: "https://www.discogs.com/release/621811"))
    }

    @Test("Resolves master ID with equals sign to title with link")
    func resolvesMasterIdWithEqualsToTitle() async {
        let input = "[m=199386]"
        var resolver = MockDiscogsEntityResolver()
        resolver.masters[199386] = "Out Of The Loop"

        let result = await DiscogsMarkupParser.parse(input, resolver: resolver)

        #expect(String(result.characters) == "Out Of The Loop")

        let range = result.startIndex..<result.endIndex
        #expect(result[range].link == URL(string: "https://www.discogs.com/master/199386"))
    }
    
    @Test("Handles mixed resolved and named tags")
    func handlesMixedResolvedAndNamedTags() async {
        let input = "[a=John Lennon] collaborated with [a999]"
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[999] = "Yoko Ono"
        
        let result = await DiscogsMarkupParser.parse(input, resolver: resolver)
        
        #expect(String(result.characters) == "John Lennon collaborated with Yoko Ono")
    }
    
    @Test("Skips unresolvable IDs gracefully")
    func skipsUnresolvableIds() async {
        let input = "See [a99999999] for more"
        let resolver = MockDiscogsEntityResolver()
        
        let result = await DiscogsMarkupParser.parse(input, resolver: resolver)
        
        #expect(String(result.characters) == "See  for more")
    }
    
    @Test("Handles resolver errors gracefully")
    func handlesResolverErrors() async {
        let input = "[a123] was great"
        var resolver = MockDiscogsEntityResolver()
        resolver.shouldThrowError = true
        
        let result = await DiscogsMarkupParser.parse(input, resolver: resolver)
        
        #expect(String(result.characters) == " was great")
    }
    
    @Test("Resolves complex real-world text")
    func resolvesComplexRealWorldText() async {
        let input = "Written by [a=John Lennon] and [a=Paul McCartney]. Produced by [a5678]. See release [r12345] for credits."
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[5678] = "George Martin"
        resolver.releases[12345] = "Sgt. Pepper's"
        
        let result = await DiscogsMarkupParser.parse(input, resolver: resolver)
    
        #expect(String(result.characters) == "Written by John Lennon and Paul McCartney. Produced by George Martin. See release Sgt. Pepper's for credits.")
    }
    
    @Test("Preserves formatting with resolved IDs")
    func preservesFormattingWithResolvedIds() async {
        let input = "[b]Bold[/b] by [a100]"
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[100] = "Test Artist"
        
        let result = await DiscogsMarkupParser.parse(input, resolver: resolver)
        
        #expect(String(result.characters) == "Bold by Test Artist")
        
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
        let input = "Artist [a1], Release [r2], Master [m3]"
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[1] = "The Artist"
        resolver.releases[2] = "The Album"
        resolver.masters[3] = "The Master"
        
        let result = await DiscogsMarkupParser.parse(input, resolver: resolver)
    
        #expect(String(result.characters) == "Artist The Artist, Release The Album, Master The Master")
    }
        
    @Test("Strips disambiguation suffix from artist names")
    func stripsDisambiguationSuffix() async {
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[1] = "Prince (2)"
        resolver.artists[2] = "Nirvana (123)"
        resolver.artists[3] = "The Beatles"
        resolver.artists[4] = "Blink-182"
        resolver.artists[5] = "Level 42"
        resolver.artists[6] = "Test (Band)"
    
        let result1 = await DiscogsMarkupParser.parse("[a1]", resolver: resolver)
        #expect(String(result1.characters) == "Prince")
        
        let result2 = await DiscogsMarkupParser.parse("[a2]", resolver: resolver)
        #expect(String(result2.characters) == "Nirvana")
        
        let result3 = await DiscogsMarkupParser.parse("[a3]", resolver: resolver)
        #expect(String(result3.characters) == "The Beatles")
        
        let result4 = await DiscogsMarkupParser.parse("[a4]", resolver: resolver)
        #expect(String(result4.characters) == "Blink-182")
        
        let result5 = await DiscogsMarkupParser.parse("[a5]", resolver: resolver)
        #expect(String(result5.characters) == "Level 42")

        let result6 = await DiscogsMarkupParser.parse("[a6]", resolver: resolver)
        #expect(String(result6.characters) == "Test (Band)")
    }

    @Test("Does not strip suffix from release or master names")
    func doesNotStripSuffixFromNonArtists() async {
        var resolver = MockDiscogsEntityResolver()
        resolver.releases[1] = "Album Title (2)"
        resolver.masters[1] = "Master Title (Remastered) (3)"

        let result1 = await DiscogsMarkupParser.parse("[r1]", resolver: resolver)
        let result2 = await DiscogsMarkupParser.parse("[m1]", resolver: resolver)

        #expect(String(result1.characters) == "Album Title (2)")
        #expect(String(result2.characters) == "Master Title (Remastered) (3)")
    }
}

// MARK: - Utility Tests

@Suite("Utility Tests")
struct UtilityTests {

    @Test("stripDisambiguationSuffix removes numeric suffix")
    func stripDisambiguationSuffixRemovesNumericSuffix() {
        #expect(DiscogsMarkupParser.stripDisambiguationSuffix(from: "Artist (2)") == "Artist")
        #expect(DiscogsMarkupParser.stripDisambiguationSuffix(from: "Artist (123)") == "Artist")
    }

    @Test("stripDisambiguationSuffix preserves non-numeric parentheses")
    func stripDisambiguationSuffixPreservesNonNumeric() {
        #expect(DiscogsMarkupParser.stripDisambiguationSuffix(from: "Artist (Band)") == "Artist (Band)")
        #expect(DiscogsMarkupParser.stripDisambiguationSuffix(from: "Level 42") == "Level 42")
    }

    @Test("stripDisambiguationSuffix handles no suffix")
    func stripDisambiguationSuffixHandlesNoSuffix() {
        #expect(DiscogsMarkupParser.stripDisambiguationSuffix(from: "Artist") == "Artist")
    }
}
