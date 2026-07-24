//
//  ConcertEventsTests.swift
//  Analytics
//
//  Property-shape and snake_case-name coverage for the OT-F2/F3 concert
//  Spotlight pipeline events (#631/OT-Q1), plus identity-free assertions:
//  none of the three events' property dictionaries may carry a concert or
//  artist id, matching the ticket's acceptance criteria.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

@Suite("Concert Spotlight donation events")
struct ConcertEventsTests {

    @Test("ConcertsDonated carries batch size and priority tier, nothing else", arguments: ["loved", "stationRecommended", "default"])
    func concertsDonatedProperties(_ tier: String) throws {
        let event = ConcertsDonated(batchSize: 3, priorityTier: tier)
        let props = try #require(event.properties)
        #expect(props["batch_size"] as? Int == 3)
        #expect(props["priority_tier"] as? String == tier)
        #expect(props.count == 2)
        #expect(ConcertsDonated.name == "concerts_donated")
    }

    @Test("ConcertsEvicted carries the evicted count, nothing else")
    func concertsEvictedProperties() throws {
        let event = ConcertsEvicted(evictedCount: 4)
        let props = try #require(event.properties)
        #expect(props["evicted_count"] as? Int == 4)
        #expect(props.count == 1)
        #expect(ConcertsEvicted.name == "concerts_evicted")
    }

    @Test("ConcertReindexRequested records the reindex kind and row count", arguments: ["single", "all"])
    func concertReindexRequestedProperties(_ kind: String) throws {
        let event = ConcertReindexRequested(kind: kind, rowCount: 9)
        let props = try #require(event.properties)
        #expect(props["kind"] as? String == kind)
        #expect(props["row_count"] as? Int == 9)
        #expect(props.count == 2)
        #expect(ConcertReindexRequested.name == "concert_reindex_requested")
    }

    // MARK: - Identity-free (acceptance criteria: no concert id, artist id, or artist name)

    @Test("No concert event property key mentions concert or artist identity")
    func noEventCarriesIdentityKeys() throws {
        let events: [any AnalyticsEvent] = [
            ConcertsDonated(batchSize: 1, priorityTier: "loved"),
            ConcertsEvicted(evictedCount: 1),
            ConcertReindexRequested(kind: "single", rowCount: 1),
        ]
        let forbiddenKeyTokens = ["concert_id", "concertid", "artist_id", "artistid", "artist_name", "artistname"]
        for event in events {
            let props = try #require(event.properties)
            for key in props.keys {
                #expect(!forbiddenKeyTokens.contains { key.localizedCaseInsensitiveContains($0) })
            }
        }
    }
}
