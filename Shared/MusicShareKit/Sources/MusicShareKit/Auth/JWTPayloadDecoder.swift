//
//  JWTPayloadDecoder.swift
//  MusicShareKit
//
//  Minimal JWT payload decoder that extracts the exp claim from a JWT string.
//  Does not verify signatures — that is the server's responsibility.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Decodes a JWT payload to extract the expiration claim.
///
/// JWTs are three base64url-encoded segments separated by dots: `header.payload.signature`.
/// This decoder only reads the payload segment to extract the `exp` claim.
enum JWTPayloadDecoder {

    /// The decoded payload containing the expiration date.
    struct Payload {
        /// When the JWT expires, derived from the `exp` claim.
        let expiresAt: Date
    }

    /// Decodes a JWT string and extracts the expiration claim.
    ///
    /// - Parameter jwt: A JWT string in the format `header.payload.signature`.
    /// - Returns: The decoded payload.
    /// - Throws: `AuthenticationError.invalidResponse` if the JWT is malformed
    ///   or missing the `exp` claim.
    static func decode(_ jwt: String) throws -> Payload {
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else {
            throw AuthenticationError.invalidResponse
        }

        let payloadSegment = String(segments[1])
        guard let data = base64urlDecode(payloadSegment) else {
            throw AuthenticationError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            throw AuthenticationError.invalidResponse
        }

        return Payload(expiresAt: Date(timeIntervalSince1970: exp))
    }

    /// Decodes a base64url-encoded string to `Data`.
    ///
    /// Normalizes URL-safe characters (`-` → `+`, `_` → `/`) and adds
    /// padding (`=`) as needed for standard base64 decoding.
    private static func base64urlDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad to a multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        return Data(base64Encoded: base64)
    }
}
