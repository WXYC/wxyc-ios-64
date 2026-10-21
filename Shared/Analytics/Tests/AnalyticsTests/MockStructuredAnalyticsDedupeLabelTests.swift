//
//  MockStructuredAnalyticsDedupeLabelTests.swift
//  Analytics
//
//  Pins that the mock records the dedupe label of each captured exception, so
//  tests of ErrorReporter conformers can assert the label reaches the gate.
//
//  Created by Jake Bromberg on 10/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Analytics
import AnalyticsTesting

@Suite("MockStructuredAnalytics dedupe labels")
struct MockStructuredAnalyticsDedupeLabelTests {

    @Test("captureException records the label of each call, in capture order")
    func recordsLabels() {
        let mock = MockStructuredAnalytics()
        let error = NSError(domain: "TestDomain", code: 1)

        mock.captureException(error, properties: nil, dedupeLabel: "playlist")
        mock.captureException(error, properties: nil, dedupeLabel: "stream")
        mock.captureException(error, properties: nil)

        #expect(mock.dedupeLabels == ["playlist", "stream", ""])
    }

    @Test("captureReportedError forwards its label to captureException")
    func reportedErrorForwardsLabel() {
        let mock = MockStructuredAnalytics()

        mock.captureReportedError(
            NSError(domain: "TestDomain", code: 1),
            context: "ctx",
            category: "Network",
            additionalData: [:],
            dedupeLabel: "playlist"
        )

        #expect(mock.dedupeLabels == ["playlist"])
    }
}
