//
//  ExceptionListScrubTests.swift
//  Analytics
//
//  Pins the pure half of the listener app's `$exception_list` privacy scrub: the query and fragment
//  of any URL in a string leaf are removed, and nothing else is rewritten. Mirrors the DJ app's
//  AnalyticsPrivacyFilterTests so the two apps treat the same SDK field the same way.
//
//  Created by Jake Bromberg on 10/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Analytics

@Suite("ExceptionListScrub")
struct ExceptionListScrubTests {
    private let dirty = "https://api.wxyc.org/library/search?artist=juana%20molina#top"
    private let clean = "https://api.wxyc.org/library/search"

    private func exceptionList(value: String, module: String = "WXYC", lineno: Int = 42) -> [String: Any] {
        [
            "$exception_list": [
                [
                    "type": "NSURLError",
                    "value": value,
                    "stacktrace": [
                        "type": "raw",
                        "frames": [["function": "fetch \(dirty)", "lineno": lineno, "in_app": true, "module": module]],
                    ] as [String: Any],
                ] as [String: Any],
            ],
        ]
    }

    private func leaves(_ properties: [String: Any]) -> (value: String?, function: String?, lineno: Int?) {
        let list = properties["$exception_list"] as? [[String: Any]]
        let frames = (list?.first?["stacktrace"] as? [String: Any])?["frames"] as? [[String: Any]]
        return (list?.first?["value"] as? String, frames?.first?["function"] as? String, frames?.first?["lineno"] as? Int)
    }

    @Test("strips the query and fragment from an exception value and a stack frame")
    func stripsQueryAndFragment() {
        let scrubbed = ExceptionListScrub.scrub(exceptionList(value: "failed: \(dirty) (-1009)"))

        let result = leaves(scrubbed)
        #expect(result.value == "failed: \(clean) (-1009)")
        #expect(result.function == "fetch \(clean)")
    }

    @Test("leaves non-string leaves untouched")
    func leavesNonStringLeavesAlone() {
        let result = leaves(ExceptionListScrub.scrub(exceptionList(value: dirty, lineno: 42)))

        #expect(result.lineno == 42)
    }

    @Test("leaves text without a URL untouched")
    func leavesPlainTextAlone() {
        #expect(leaves(ExceptionListScrub.scrub(exceptionList(value: "The operation couldn't be completed.")))
            .value == "The operation couldn't be completed.")
    }

    @Test("does not rewrite other $ keys, even when they hold a URL")
    func leavesOtherKeysAlone() {
        var properties = exceptionList(value: dirty)
        properties["$current_url"] = dirty
        properties["$lib"] = "posthog-ios"

        let scrubbed = ExceptionListScrub.scrub(properties)

        #expect(scrubbed["$current_url"] as? String == dirty)
        #expect(scrubbed["$lib"] as? String == "posthog-ios")
    }

    @Test("an event with no $exception_list passes through")
    func passesThroughWithoutExceptionList() {
        #expect(ExceptionListScrub.scrub(["$lib": "posthog-ios"]) as? [String: String] == ["$lib": "posthog-ios"])
    }
}
