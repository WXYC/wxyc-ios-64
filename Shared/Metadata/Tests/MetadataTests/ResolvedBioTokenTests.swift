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
import WXYCAPIModels
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

// MARK: - Generated Wire Type Mapping Tests

/// Covers the degrading seam `ResolvedBioToken.init?(_ token: WXYCAPIModels.DiscogsResolvedToken)`,
/// which maps the generated wire type (api.yaml's `DiscogsResolvedToken`) onto this hand-written
/// domain type. See WXYC/wxyc-ios-64#601 "Settled design" for the tolerant-degrade rules this
/// seam must follow: an unknown `type` drops the token (`nil`, filtered out by `compactMap`), and
/// a known `type` missing a required field (or carrying a URL string that fails `URL(string:)`)
/// degrades to `.plainText` of the best available text field rather than failing the whole decode.
@Suite("ResolvedBioToken(_ token: DiscogsResolvedToken) Wire Mapping")
struct ResolvedBioTokenWireMappingTests {

    // MARK: Every known variant maps generated -> domain

    @Test("Maps plainText")
    func mapsPlainText() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .plaintext, text: "Juana Molina is an Argentine singer-songwriter.")
        #expect(ResolvedBioToken(wire) == .plainText("Juana Molina is an Argentine singer-songwriter."))
    }

    @Test("Maps artistLink")
    func mapsArtistLink() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(
            type: .artistlink,
            name: "Stereolab",
            displayName: "Stereolab",
            url: "https://www.discogs.com/artist/8231"
        )
        #expect(ResolvedBioToken(wire) == .artistLink(
            name: "Stereolab",
            displayName: "Stereolab",
            url: URL(string: "https://www.discogs.com/artist/8231")!
        ))
    }

    @Test("Maps labelName")
    func mapsLabelName() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .labelname, name: "Drag City")
        #expect(ResolvedBioToken(wire) == .labelName("Drag City"))
    }

    @Test("Maps releaseLink")
    func mapsReleaseLink() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(
            type: .releaselink,
            title: "On Your Own Love Again",
            url: "https://www.discogs.com/release/111"
        )
        #expect(ResolvedBioToken(wire) == .releaseLink(
            title: "On Your Own Love Again",
            url: URL(string: "https://www.discogs.com/release/111")!
        ))
    }

    @Test("Maps masterLink")
    func mapsMasterLink() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(
            type: .masterlink,
            title: "DOGA",
            url: "https://www.discogs.com/master/222"
        )
        #expect(ResolvedBioToken(wire) == .masterLink(
            title: "DOGA",
            url: URL(string: "https://www.discogs.com/master/222")!
        ))
    }

    @Test("Maps bold")
    func mapsBold() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .bold, content: "essential listening")
        #expect(ResolvedBioToken(wire) == .bold("essential listening"))
    }

    @Test("Maps italic")
    func mapsItalic() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .italic, content: "Call Your Name")
        #expect(ResolvedBioToken(wire) == .italic("Call Your Name"))
    }

    @Test("Maps underline")
    func mapsUnderline() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .underline, content: "self-released")
        #expect(ResolvedBioToken(wire) == .underline("self-released"))
    }

    @Test("Maps urlLink with an href")
    func mapsUrlLinkWithHref() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .urllink, href: "https://chuquimamanicondori.bandcamp.com", content: "Bandcamp")
        #expect(ResolvedBioToken(wire) == .urlLink(URL(string: "https://chuquimamanicondori.bandcamp.com"), "Bandcamp"))
    }

    @Test("Maps urlLink with no href")
    func mapsUrlLinkWithoutHref() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .urllink, content: "dead link")
        #expect(ResolvedBioToken(wire) == .urlLink(nil, "dead link"))
    }

    // MARK: Unknown type is dropped

    @Test("Unknown type maps to nil, dropped by compactMap")
    func unknownTypeMapsToNil() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .unknownDefaultOpenApi, text: "some future shape")
        #expect(ResolvedBioToken(wire) == nil)
    }

    @Test("compactMap drops unknown tokens but keeps their neighbors")
    func compactMapDropsUnknownTokens() {
        let wire: [WXYCAPIModels.DiscogsResolvedToken] = [
            .init(type: .plaintext, text: "Duo of "),
            .init(type: .unknownDefaultOpenApi, text: "unrecognized"),
            .init(type: .plaintext, text: "."),
        ]
        let mapped = wire.compactMap(ResolvedBioToken.init)
        #expect(mapped == [.plainText("Duo of "), .plainText(".")])
    }

    // MARK: Missing required field degrades to plainText, never throws

    @Test("artistLink missing url degrades to plainText using displayName")
    func artistLinkMissingURLDegrades() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .artistlink, name: "Cat Power", displayName: "Cat Power")
        #expect(ResolvedBioToken(wire) == .plainText("Cat Power"))
    }

    @Test("artistLink missing name and displayName degrades using the raw name field's absence, falling back to title")
    func artistLinkMissingNameFieldsDegrades() {
        // No displayName/title/content/text present, only `name` -- lowest-priority fallback.
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .artistlink, name: "Jessica Pratt", url: nil)
        #expect(ResolvedBioToken(wire) == .plainText("Jessica Pratt"))
    }

    @Test("releaseLink missing title degrades to plainText")
    func releaseLinkMissingTitleDegrades() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .releaselink, url: "https://www.discogs.com/release/333")
        #expect(ResolvedBioToken(wire) == .plainText(""))
    }

    @Test("masterLink missing url degrades to plainText using title")
    func masterLinkMissingURLDegrades() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .masterlink, title: "Edits")
        #expect(ResolvedBioToken(wire) == .plainText("Edits"))
    }

    @Test("labelName missing name degrades to plainText")
    func labelNameMissingNameDegrades() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .labelname)
        #expect(ResolvedBioToken(wire) == .plainText(""))
    }

    @Test("bold missing content degrades to plainText using text")
    func boldMissingContentDegrades() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .bold, text: "fallback text")
        #expect(ResolvedBioToken(wire) == .plainText("fallback text"))
    }

    @Test("italic missing content degrades to plainText")
    func italicMissingContentDegrades() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .italic)
        #expect(ResolvedBioToken(wire) == .plainText(""))
    }

    @Test("underline missing content degrades to plainText")
    func underlineMissingContentDegrades() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .underline)
        #expect(ResolvedBioToken(wire) == .plainText(""))
    }

    @Test("urlLink missing content degrades to plainText")
    func urlLinkMissingContentDegrades() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .urllink, href: "https://example.com")
        #expect(ResolvedBioToken(wire) == .plainText(""))
    }

    // MARK: Invalid URL string degrades to plainText, never throws

    @Test("artistLink with an invalid url string degrades to plainText")
    func artistLinkInvalidURLDegrades() {
        // A string containing raw whitespace and control-like content is not a valid URL.
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .artistlink, name: "Hermanos Gutiérrez", displayName: "Hermanos Gutiérrez", url: "")
        #expect(ResolvedBioToken(wire) == .plainText("Hermanos Gutiérrez"))
    }

    @Test("releaseLink with an invalid url string degrades to plainText")
    func releaseLinkInvalidURLDegrades() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .releaselink, title: "Aluminum Tunes", url: "")
        #expect(ResolvedBioToken(wire) == .plainText("Aluminum Tunes"))
    }

    @Test("urlLink with an invalid href string degrades to plainText")
    func urlLinkInvalidHrefDegrades() {
        let wire = WXYCAPIModels.DiscogsResolvedToken(type: .urllink, href: "", content: "broken link")
        #expect(ResolvedBioToken(wire) == .plainText("broken link"))
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
