//
//  ExceptionListScrub.swift
//  Analytics
//
//  Removes URL queries and fragments from the `$exception_list` of a PostHog `$exception` event.
//  Pure Foundation, so it is unit-testable without linking PostHog; `AnalyticsBootstrap.start`
//  calls it from the SDK's before-send hook.
//
//  The URL rule is copied from the DJ app (`URLScrubbing` and `TelemetryPrivacyScrub` in
//  wxyc-dj-ios) so the two apps treat the same SDK field the same way.
//
//  Created by Jake Bromberg on 10/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Scrubs the query string and fragment from every URL inside an event's `$exception_list`.
///
/// posthog-ios builds `$exception_list` from the error's description, its `NSDebugDescriptionErrorKey`
/// and its `NSUnderlyingErrorKey` chain, and a URLSession error can put the failing request URL, with
/// its query string, into any of them. A query string can carry search text or tokens. Every other
/// property is left alone.
enum ExceptionListScrub {
    private static let exceptionListKey = "$exception_list"

    /// Returns `properties` with every string leaf of `$exception_list` scrubbed.
    ///
    /// - Parameter properties: An event's properties as the SDK assembled them.
    /// - Returns: The same properties, with only `$exception_list` rewritten.
    static func scrub(_ properties: [String: Any]) -> [String: Any] {
        guard let exceptionList = properties[exceptionListKey] else {
            return properties
        }
        var scrubbed = properties
        scrubbed[exceptionListKey] = scrubLeaves(of: exceptionList)
        return scrubbed
    }

    /// Recurses through dictionaries and arrays, scrubbing strings. Numbers, bools and the like pass through.
    private static func scrubLeaves(of value: Any) -> Any {
        switch value {
        case let string as String:
            return scrubEmbeddedURLs(in: string)
        case let dictionary as [String: Any]:
            return dictionary.mapValues(scrubLeaves(of:))
        case let array as [Any]:
            return array.map(scrubLeaves(of:))
        default:
            return value
        }
    }

    /// Strips the query and fragment from every URL found inside free-form text.
    ///
    /// Exception values embed URLs as substrings of a larger description
    /// (`UserInfo={NSErrorFailingURLStringKey=https://…?q=…}`), so a whole-string check would miss
    /// them. `NSDataDetector` finds each link; characters outside a detected URL are untouched.
    static func scrubEmbeddedURLs(in text: String) -> String {
        guard let detector = linkDetector else {
            return text
        }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))

        var result = text
        // Back-to-front, so each replacement leaves the ranges of the matches still to come valid.
        for match in matches.reversed() {
            guard let url = match.url, let range = Range(match.range, in: result) else {
                continue
            }
            let scrubbedURL = strippingQueryAndFragment(of: url)
            if scrubbedURL != url {
                result.replaceSubrange(range, with: scrubbedURL.absoluteString)
            }
        }
        return result
    }

    private static func strippingQueryAndFragment(of url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    /// Built once: `NSDataDetector` parses a grammar on construction and is safe to reuse.
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
}
