//
//  ResolvedBioTokenTests.swift
//  Metadata
//
//  Tests for ResolvedBioToken JSON decoding, encoding, and rendering.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Metadata

// MARK: - JSON Decoding Tests

@Suite("ResolvedBioToken JSON Decoding")
struct ResolvedBioTokenDecodingTests {

    @Test("Decodes plainText token")
    func decodesPlainText() throws {
        let json = #"{"type": "plainText", "text": "Autechre is a duo."}"#
        let token = try decode(json)
        #expect(token == .plainText("Autechre is a duo."))
    }

    @Test("Decodes artistLink token with display_name")
    func decodesArtistLink() throws {
        let json = #"{"type": "artistLink", "name": "Salamanda (8)", "display_name": "Salamanda", "url": "https://www.discogs.com/artist/8390436"}"#
        let token = try decode(json)
        #expect(token == .artistLink(
            name: "Salamanda (8)",
            displayName: "Salamanda",
            url: URL(string: "https://www.discogs.com/artist/8390436")!
        ))
    }

    @Test("Decodes labelName token")
    func decodesLabelName() throws {
        let json = #"{"type": "labelName", "name": "Warp"}"#
        let token = try decode(json)
        #expect(token == .labelName("Warp"))
    }

    @Test("Decodes releaseLink token")
    func decodesReleaseLink() throws {
        let json = #"{"type": "releaseLink", "title": "Confield", "url": "https://www.discogs.com/release/99999"}"#
        let token = try decode(json)
        #expect(token == .releaseLink(
            title: "Confield",
            url: URL(string: "https://www.discogs.com/release/99999")!
        ))
    }

    @Test("Decodes masterLink token")
    func decodesMasterLink() throws {
        let json = #"{"type": "masterLink", "title": "Kind of Blue", "url": "https://www.discogs.com/master/12345"}"#
        let token = try decode(json)
        #expect(token == .masterLink(
            title: "Kind of Blue",
            url: URL(string: "https://www.discogs.com/master/12345")!
        ))
    }

    @Test("Decodes bold token")
    func decodesBold() throws {
        let json = #"{"type": "bold", "content": "important"}"#
        let token = try decode(json)
        #expect(token == .bold("important"))
    }

    @Test("Decodes italic token")
    func decodesItalic() throws {
        let json = #"{"type": "italic", "content": "emphasized"}"#
        let token = try decode(json)
        #expect(token == .italic("emphasized"))
    }

    @Test("Decodes underline token")
    func decodesUnderline() throws {
        let json = #"{"type": "underline", "content": "underlined"}"#
        let token = try decode(json)
        #expect(token == .underline("underlined"))
    }

    @Test("Decodes urlLink token with valid href")
    func decodesUrlLink() throws {
        let json = #"{"type": "urlLink", "href": "https://autechre.ws", "content": "website"}"#
        let token = try decode(json)
        #expect(token == .urlLink(URL(string: "https://autechre.ws"), "website"))
    }

    @Test("Decodes urlLink token with null href")
    func decodesUrlLinkWithNullHref() throws {
        let json = #"{"type": "urlLink", "href": null, "content": "broken link"}"#
        let token = try decode(json)
        #expect(token == .urlLink(nil, "broken link"))
    }

    @Test("Decodes unknown token type as empty plainText")
    func decodesUnknownType() throws {
        let json = #"{"type": "futureType", "data": "something"}"#
        let token = try decode(json)
        #expect(token == .plainText(""))
    }

    @Test("Decodes array of mixed tokens")
    func decodesTokenArray() throws {
        let json = #"""
        [
            {"type": "plainText", "text": "Duo of "},
            {"type": "artistLink", "name": "Rob Brown", "display_name": "Rob Brown", "url": "https://www.discogs.com/search/?q=Rob%20Brown&type=artist"},
            {"type": "plainText", "text": " and "},
            {"type": "artistLink", "name": "Sean Booth", "display_name": "Sean Booth", "url": "https://www.discogs.com/search/?q=Sean%20Booth&type=artist"},
            {"type": "plainText", "text": "."}
        ]
        """#
        let tokens = try JSONDecoder().decode([ResolvedBioToken].self, from: Data(json.utf8))
        #expect(tokens.count == 5)
        #expect(tokens[0] == .plainText("Duo of "))
        #expect(tokens[4] == .plainText("."))
    }
}

// MARK: - Round-Trip Tests

@Suite("ResolvedBioToken Round-Trip")
struct ResolvedBioTokenRoundTripTests {

    @Test("plainText survives encode/decode")
    func roundTripPlainText() throws {
        try assertRoundTrip(.plainText("hello"))
    }

    @Test("artistLink survives encode/decode")
    func roundTripArtistLink() throws {
        try assertRoundTrip(.artistLink(
            name: "Juana Molina",
            displayName: "Juana Molina",
            url: URL(string: "https://www.discogs.com/artist/123")!
        ))
    }

    @Test("releaseLink survives encode/decode")
    func roundTripReleaseLink() throws {
        try assertRoundTrip(.releaseLink(
            title: "DOGA",
            url: URL(string: "https://www.discogs.com/release/456")!
        ))
    }

    @Test("urlLink with nil href survives encode/decode")
    func roundTripUrlLinkNilHref() throws {
        try assertRoundTrip(.urlLink(nil, "link text"))
    }

    @Test("urlLink with valid href survives encode/decode")
    func roundTripUrlLinkValidHref() throws {
        try assertRoundTrip(.urlLink(URL(string: "https://example.com"), "link"))
    }
}

// MARK: - Rendering Tests

@Suite("ResolvedBioToken Rendering")
struct ResolvedBioTokenRenderingTests {

    @Test("Renders plainText")
    func rendersPlainText() {
        let result = ResolvedBioToken.render([.plainText("hello world")])
        #expect(String(result.characters) == "hello world")
    }

    @Test("Renders artistLink with displayName")
    func rendersArtistLink() {
        let result = ResolvedBioToken.render([
            .artistLink(
                name: "Salamanda (8)",
                displayName: "Salamanda",
                url: URL(string: "https://www.discogs.com/artist/8390436")!
            )
        ])
        #expect(String(result.characters) == "Salamanda")

        let range = result.startIndex..<result.endIndex
        #expect(result[range].link == URL(string: "https://www.discogs.com/artist/8390436"))
    }

    @Test("Renders releaseLink with title")
    func rendersReleaseLink() {
        let result = ResolvedBioToken.render([
            .releaseLink(title: "Confield", url: URL(string: "https://www.discogs.com/release/99999")!)
        ])
        #expect(String(result.characters) == "Confield")
    }

    @Test("Renders bold with stronglyEmphasized intent")
    func rendersBold() {
        let result = ResolvedBioToken.render([.bold("important")])
        #expect(String(result.characters) == "important")

        var found = false
        for run in result.runs {
            if run.inlinePresentationIntent == .stronglyEmphasized {
                found = true
            }
        }
        #expect(found)
    }

    @Test("Renders italic with emphasized intent")
    func rendersItalic() {
        let result = ResolvedBioToken.render([.italic("noted")])
        #expect(String(result.characters) == "noted")

        var found = false
        for run in result.runs {
            if run.inlinePresentationIntent == .emphasized {
                found = true
            }
        }
        #expect(found)
    }

    @Test("Renders urlLink with nil href as text without link")
    func rendersUrlLinkNilHref() {
        let result = ResolvedBioToken.render([.urlLink(nil, "broken")])
        #expect(String(result.characters) == "broken")

        for run in result.runs {
            #expect(run.link == nil)
        }
    }

    @Test("Renders mixed tokens to continuous text")
    func rendersMixedTokens() {
        let tokens: [ResolvedBioToken] = [
            .plainText("Written by "),
            .artistLink(name: "Juana Molina", displayName: "Juana Molina", url: URL(string: "https://www.discogs.com/artist/123")!),
            .plainText(". Released on "),
            .labelName("Sonamos"),
            .plainText("."),
        ]
        let result = ResolvedBioToken.render(tokens)
        #expect(String(result.characters) == "Written by Juana Molina. Released on Sonamos.")
    }

    @Test("Renders empty array to empty string")
    func rendersEmptyArray() {
        let result = ResolvedBioToken.render([])
        #expect(String(result.characters) == "")
    }

    @Test("Rendering matches DiscogsMarkupParser output for equivalent tokens")
    func renderingMatchesParserOutput() {
        let bio = "[b]Bold[/b] text by [a=Cat Power] on [l=Matador Records]."
        let parserResult = DiscogsMarkupParser.parse(bio)

        let serverTokens: [ResolvedBioToken] = [
            .bold("Bold"),
            .plainText(" text by "),
            .artistLink(
                name: "Cat Power",
                displayName: "Cat Power",
                url: URL(string: "https://www.discogs.com/search/?q=Cat%20Power&type=artist")!
            ),
            .plainText(" on "),
            .labelName("Matador Records"),
            .plainText("."),
        ]
        let serverResult = ResolvedBioToken.render(serverTokens)

        #expect(String(parserResult.characters) == String(serverResult.characters))
    }
}

// MARK: - Helpers

private func decode(_ json: String) throws -> ResolvedBioToken {
    try JSONDecoder().decode(ResolvedBioToken.self, from: Data(json.utf8))
}

private func assertRoundTrip(_ token: ResolvedBioToken) throws {
    let encoded = try JSONEncoder().encode(token)
    let decoded = try JSONDecoder().decode(ResolvedBioToken.self, from: encoded)
    #expect(decoded == token)
}
