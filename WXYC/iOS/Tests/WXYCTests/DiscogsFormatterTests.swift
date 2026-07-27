//
//  DiscogsFormatterTests.swift
//  WXYC
//
//  SwiftUI-specific tests for DiscogsFormatter
//
//  These tests verify the SwiftUI-specific styling applied by DiscogsFormatter
//  on top of the Foundation-based DiscogsMarkupParser.
//
//  Parser logic tests are in MetadataTests/DiscogsMarkupParserTests.swift
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
import SwiftUI
@testable import WXYC
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

// MARK: - SwiftUI Styling Tests

@Suite("SwiftUI Link Styling Tests")
struct SwiftUILinkStylingTests {
    
    @Test("URL link has secondary foreground color")
    func urlLinkHasSecondaryColor() {
        let input = "[url=https://example.com]Link[/url]"
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        var hasSecondaryColor = false
        for run in result.runs {
            if run.foregroundColor == .secondary {
                hasSecondaryColor = true
                break
            }
        }
        #expect(hasSecondaryColor)
    }
    
    @Test("Artist name link has secondary foreground color")
    func artistNameLinkHasSecondaryColor() {
        let input = "[a=The Beatles]"
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        var hasSecondaryColor = false
        for run in result.runs {
            if run.link != nil && run.foregroundColor == .secondary {
                hasSecondaryColor = true
                break
            }
        }
        #expect(hasSecondaryColor)
    }
    
    @Test("Resolved artist ID link has secondary foreground color")
    func resolvedArtistIdLinkHasSecondaryColor() async {
        let input = "[a123]"
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[123] = "Test Artist"
        
        let result = await DiscogsFormatter.parseToAttributedString(input, resolver: resolver)
        
        var hasSecondaryColor = false
        for run in result.runs {
            if run.link != nil && run.foregroundColor == .secondary {
                hasSecondaryColor = true
                break
            }
        }
        #expect(hasSecondaryColor)
    }
    
    @Test("Resolved release ID link has secondary foreground color")
    func resolvedReleaseIdLinkHasSecondaryColor() async {
        let input = "[r456]"
        var resolver = MockDiscogsEntityResolver()
        resolver.releases[456] = "Test Album"
        
        let result = await DiscogsFormatter.parseToAttributedString(input, resolver: resolver)
        
        var hasSecondaryColor = false
        for run in result.runs {
            if run.link != nil && run.foregroundColor == .secondary {
                hasSecondaryColor = true
                break
            }
        }
        #expect(hasSecondaryColor)
    }
    
    @Test("Resolved master ID link has secondary foreground color")
    func resolvedMasterIdLinkHasSecondaryColor() async {
        let input = "[m789]"
        var resolver = MockDiscogsEntityResolver()
        resolver.masters[789] = "Test Master"
        
        let result = await DiscogsFormatter.parseToAttributedString(input, resolver: resolver)
        
        var hasSecondaryColor = false
        for run in result.runs {
            if run.link != nil && run.foregroundColor == .secondary {
                hasSecondaryColor = true
                break
            }
        }
        #expect(hasSecondaryColor)
    }
    
    @Test("URL has all required SwiftUI attributes")
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
    
    @Test("Plain text has no foreground color")
    func plainTextHasNoForegroundColor() {
        let result = DiscogsFormatter.parseToAttributedString("plain text")
    
        for run in result.runs {
            #expect(run.foregroundColor == nil)
        }
    }
    
    @Test("Non-link formatted text has no foreground color")
    func nonLinkFormattedTextHasNoForegroundColor() {
        let result = DiscogsFormatter.parseToAttributedString("[b]bold[/b] and [i]italic[/i]")
    
        for run in result.runs {
            #expect(run.foregroundColor == nil)
        }
    }
    
    @Test("Multiple links all have secondary color")
    func multipleLinksAllHaveSecondaryColor() {
        let input = "[a=Artist One] and [url=https://example.com]link[/url]"
        let result = DiscogsFormatter.parseToAttributedString(input)
        
        var linkCount = 0
        var secondaryColorCount = 0
        
        for run in result.runs {
            if run.link != nil {
                linkCount += 1
                if run.foregroundColor == .secondary {
                    secondaryColorCount += 1
                }
            }
        }

        #expect(linkCount == 2)
        #expect(secondaryColorCount == 2)
    }
}

// MARK: - resolvedBio Seam Tests

/// Covers `DiscogsFormatter.resolvedBio(bio:bioTokens:resolver:)`, the seam
/// `ArtistBioSection`'s `.task` calls to decide between rendering pre-parsed server
/// `bioTokens` and falling back to client-side string parsing with an injected
/// resolver. This is the seam that exercises the resolver-auth fix end to end at the
/// app layer, with a resolver test doubles control -- see
/// `ArtistBioSection.init(bio:bioTokens:expandedBio:showsHeader:resolver:)`.
@Suite("DiscogsFormatter.resolvedBio Seam Tests")
struct DiscogsFormatterResolvedBioSeamTests {

    @Test("bioTokens present renders the token names without touching the resolver")
    func rendersServerTokensWithoutResolver() async {
        let tokens: [ResolvedBioToken] = [
            .plainText("Duo of "),
            .artistLink(
                name: "Juana Molina",
                displayName: "Juana Molina",
                url: URL(string: "https://www.discogs.com/artist/123")!
            ),
            .plainText("."),
        ]
        // A `bio` string that renders very differently if the resolver/string-parse
        // path were taken by mistake -- proves bioTokens short-circuits it entirely.
        let mismatchedBio = "[a999] should never be parsed"
        var resolver = MockDiscogsEntityResolver()
        resolver.shouldThrowError = true

        let result = await DiscogsFormatter.resolvedBio(bio: mismatchedBio, bioTokens: tokens, resolver: resolver)

        #expect(String(result.characters) == "Duo of Juana Molina.")
    }

    @Test("bioTokens nil with a working resolver resolves both artist names")
    func resolvesBothNamesWithWorkingResolver() async {
        let bio = "Member of the electronica duo [a87717], formed with his sibling [a325359]."
        var resolver = MockDiscogsEntityResolver()
        resolver.artists[87717] = "The Knife"
        resolver.artists[325359] = "Karin Dreijer"

        let result = await DiscogsFormatter.resolvedBio(bio: bio, bioTokens: nil, resolver: resolver)

        #expect(String(result.characters) == "Member of the electronica duo The Knife, formed with his sibling Karin Dreijer.")
    }

    @Test("bioTokens nil with a throwing resolver (simulating an unauthenticated 401) renders the gracefully coalesced output")
    func gracefullyDegradesWithThrowingResolver() async {
        let bio = "Member of the electronica duo [a87717], formed with his sibling [a325359]."
        var resolver = MockDiscogsEntityResolver()
        resolver.shouldThrowError = true

        let result = await DiscogsFormatter.resolvedBio(bio: bio, bioTokens: nil, resolver: resolver)

        #expect(String(result.characters) == "Member of the electronica duo, formed with his sibling.")
    }
}
