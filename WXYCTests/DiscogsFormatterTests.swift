//
//  DiscogsFormatterTests.swift
//  WXYCTests
//
//  SwiftUI-specific tests for DiscogsFormatter
//
//  These tests verify the SwiftUI-specific styling applied by DiscogsFormatter
//  on top of the Foundation-based DiscogsMarkupParser.
//
//  Parser logic tests are in MetadataTests/DiscogsMarkupParserTests.swift
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
