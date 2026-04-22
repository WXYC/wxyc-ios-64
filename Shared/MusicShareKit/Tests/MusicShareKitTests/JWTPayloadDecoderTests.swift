//
//  JWTPayloadDecoderTests.swift
//  MusicShareKit
//
//  Tests for JWTPayloadDecoder base64url decoding and exp claim extraction.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import MusicShareKit

@Suite("JWTPayloadDecoder Tests")
struct JWTPayloadDecoderTests {

    // MARK: - Helpers

    /// Encodes a JSON payload as a base64url segment (no padding).
    private func base64urlEncode(_ json: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Builds a fake JWT string with the given payload segment.
    private func makeJWT(payload: String) -> String {
        "eyJhbGciOiJIUzI1NiJ9.\(payload).fakesignature"
    }

    /// Builds a fake JWT from a JSON dictionary.
    private func makeJWT(claims: [String: Any]) -> String {
        makeJWT(payload: base64urlEncode(claims))
    }

    // MARK: - Success Cases

    @Test("Decodes valid JWT with exp claim")
    func decodesValidJWTWithExpClaim() throws {
        let expTimestamp: TimeInterval = 1735689600 // 2025-01-01T00:00:00Z
        let jwt = makeJWT(claims: ["sub": "user123", "exp": expTimestamp])

        let payload = try JWTPayloadDecoder.decode(jwt)

        #expect(payload.expiresAt == Date(timeIntervalSince1970: expTimestamp))
    }

    @Test("Handles base64url characters (- and _)")
    func handlesBase64URLCharacters() throws {
        // Create a payload whose base64 encoding contains + and / characters.
        // Use a payload with bytes that produce those characters.
        let claims: [String: Any] = [
            "exp": 1735689600,
            "sub": "user???>>><<<" // likely to produce +/_ in base64
        ]
        let jwt = makeJWT(claims: claims)

        let payload = try JWTPayloadDecoder.decode(jwt)

        #expect(payload.expiresAt == Date(timeIntervalSince1970: 1735689600))
    }

    @Test("Handles payload without base64 padding")
    func handlesPayloadWithoutPadding() throws {
        // Payloads are stripped of = padding in JWTs
        let claims: [String: Any] = ["exp": 1735689600]
        let encoded = base64urlEncode(claims)
        // Verify our helper actually stripped padding
        #expect(!encoded.contains("="))

        let jwt = makeJWT(payload: encoded)
        let payload = try JWTPayloadDecoder.decode(jwt)

        #expect(payload.expiresAt == Date(timeIntervalSince1970: 1735689600))
    }

    @Test("Decodes exp as integer")
    func decodesExpAsInteger() throws {
        // exp is typically an integer in JWT payloads
        let jwt = makeJWT(claims: ["exp": 1893456000]) // 2030-01-01

        let payload = try JWTPayloadDecoder.decode(jwt)

        #expect(payload.expiresAt == Date(timeIntervalSince1970: 1893456000))
    }

    // MARK: - Failure Cases

    @Test("Throws for token with wrong segment count")
    func throwsForWrongSegmentCount() {
        #expect(throws: AuthenticationError.self) {
            _ = try JWTPayloadDecoder.decode("a.b.c.d.e")
        }
    }

    @Test("Throws for single-segment token")
    func throwsForSingleSegment() {
        #expect(throws: AuthenticationError.self) {
            _ = try JWTPayloadDecoder.decode("noperiods")
        }
    }

    @Test("Throws for invalid base64 in payload segment")
    func throwsForInvalidBase64() {
        #expect(throws: AuthenticationError.self) {
            _ = try JWTPayloadDecoder.decode("header.!!!invalid!!!.signature")
        }
    }

    @Test("Throws for missing exp claim in payload")
    func throwsForMissingExpClaim() {
        let jwt = makeJWT(claims: ["sub": "user123", "iat": 1735689600])

        #expect(throws: AuthenticationError.self) {
            _ = try JWTPayloadDecoder.decode(jwt)
        }
    }

    @Test("Throws for empty string")
    func throwsForEmptyString() {
        #expect(throws: AuthenticationError.self) {
            _ = try JWTPayloadDecoder.decode("")
        }
    }
}
