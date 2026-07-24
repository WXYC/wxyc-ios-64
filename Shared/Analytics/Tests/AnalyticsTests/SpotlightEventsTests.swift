//
//  SpotlightEventsTests.swift
//  Analytics
//
//  Property-shape and snake_case-name coverage for the Spotlight donation
//  pipeline events (#445).
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

@Suite("Spotlight donation events")
struct SpotlightEventsTests {

    @Test("SpotlightDonated carries playcut id, batch size, and priority tier")
    func spotlightDonatedProperties() throws {
        let event = SpotlightDonated(playcutID: "1234", batchSize: 12, priorityTier: 100)
        let props = try #require(event.properties)
        #expect(props["playcut_id"] as? String == "1234")
        #expect(props["batch_size"] as? Int == 12)
        #expect(props["priority_tier"] as? Int == 100)
        #expect(props.count == 3)
        #expect(SpotlightDonated.name == "spotlight_donated")
    }

    @Test("SpotlightDonationFailed carries error kind and batch size, nothing else")
    func spotlightDonationFailedProperties() throws {
        let event = SpotlightDonationFailed(errorKind: "NSCocoaErrorDomain", batchSize: 5)
        let props = try #require(event.properties)
        #expect(props["error_kind"] as? String == "NSCocoaErrorDomain")
        #expect(props["batch_size"] as? Int == 5)
        #expect(props.count == 2)
        #expect(SpotlightDonationFailed.name == "spotlight_donation_failed")
    }

    @Test("SpotlightReindexRequested records the reindex kind and row count", arguments: ["single", "all"])
    func spotlightReindexRequestedProperties(_ kind: String) throws {
        let event = SpotlightReindexRequested(kind: kind, rowCount: 7)
        let props = try #require(event.properties)
        #expect(props["kind"] as? String == kind)
        #expect(props["row_count"] as? Int == 7)
        #expect(props.count == 2)
        #expect(SpotlightReindexRequested.name == "spotlight_reindex_requested")
    }
}
