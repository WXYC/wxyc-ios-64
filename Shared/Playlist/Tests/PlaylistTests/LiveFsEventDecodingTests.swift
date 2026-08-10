//
//  LiveFsEventDecodingTests.swift
//  Playlist
//
//  Verifies LiveFsEvent.init(frameData:) decodes each modeled event type from
//  the Backend `live-fs-topic` SSE contract (insert/update/refetch), maps the
//  row payloads through FlowsheetConverter, and tolerantly drops the stream's
//  envelope frames, heartbeats, unknown types, malformed JSON, and non-track
//  rows. See WXYC/wxyc-ios-64#269.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("LiveFsEvent decoding")
struct LiveFsEventDecodingTests {

    private func decode(_ json: String) -> LiveFsEvent? {
        LiveFsEvent(frameData: Data(json.utf8))
    }

    @Test("An insert frame decodes to .insert with the row mapped to a Playcut")
    func decodesInsert() throws {
        let json = """
        {
          "type": "insert",
          "payload": {
            "id": 90210,
            "show_id": 5,
            "album_id": null,
            "artist_name": "Juana Molina",
            "album_title": "DOGA",
            "track_title": "la paradoja",
            "record_label": "Sonamos",
            "rotation_id": null,
            "play_order": 3,
            "add_time": "2026-07-31T18:00:00Z",
            "entry_type": "track",
            "metadata_status": "pending"
          },
          "timestamp": "2026-07-31T18:00:00Z"
        }
        """
        guard case let .insert(playcut) = try #require(decode(json)) else {
            Issue.record("expected .insert")
            return
        }
        #expect(playcut.id == 90210)
        #expect(playcut.artistName == "Juana Molina")
        #expect(playcut.songTitle == "la paradoja")
        #expect(playcut.releaseTitle == "DOGA")
        #expect(playcut.metadataStatus == .pending)
        // A pending insert carries no enrichment yet.
        #expect(playcut.artworkURL == nil)
    }

    @Test("An update frame decodes to .update carrying the finalized enrichment fields")
    func decodesUpdate() throws {
        let json = """
        {
          "type": "update",
          "payload": {
            "id": 90210,
            "show_id": 5,
            "artist_name": "Juana Molina",
            "album_title": "DOGA",
            "track_title": "la paradoja",
            "play_order": 3,
            "add_time": "2026-07-31T18:00:00Z",
            "entry_type": "track",
            "artwork_url": "https://example.com/art.jpg",
            "release_year": 2024,
            "metadata_status": "enriched_match"
          },
          "timestamp": "2026-07-31T18:00:05Z"
        }
        """
        guard case let .update(playcut) = try #require(decode(json)) else {
            Issue.record("expected .update")
            return
        }
        #expect(playcut.id == 90210)
        #expect(playcut.artworkURL == URL(string: "https://example.com/art.jpg"))
        #expect(playcut.releaseYear == 2024)
        #expect(playcut.metadataStatus == .enrichedMatch)
        // `show_id` belongs on this payload and the fixture has to carry it:
        // `PlaylistService.upsertPlaycut` replaces the stored row wholesale,
        // so an update frame that arrived without it would rewrite a packed
        // key (~8.4e15) down to the bare-id fallback and drop the on-air song
        // to the bottom of the feed mid-play. Backend does send it — both
        // `show_id` and `play_order` are on `CLIENT_FACING_FLOWSHEET_COLUMNS`
        // (`flowsheet-projection.ts`), the allow-list the CDC row is projected
        // through before it reaches `live-fs-topic`. Asserting the derived key
        // here is what would notice if that allow-list ever changed under us.
        #expect(playcut.chronOrderID == (UInt64(5) << 32) | 3)
    }

    @Test("A refetch frame decodes to .refetch carrying the telemetry source")
    func decodesRefetch() throws {
        let json = """
        { "type": "refetch", "payload": { "source": "etl" }, "timestamp": "2026-07-31T18:00:00Z" }
        """
        guard case let .refetch(source) = try #require(decode(json)) else {
            Issue.record("expected .refetch")
            return
        }
        #expect(source == "etl")
    }

    @Test(
        "Envelope, heartbeat-shaped, unknown-type, and malformed frames all decode to nil",
        arguments: [
            // connection-established envelope (first frame of every stream)
            #"{ "type": "connection-established", "payload": { "clientId": "abc" }, "timestamp": "2026-07-31T18:00:00Z" }"#,
            // subscription envelope
            #"{ "type": "subscription", "payload": { "client_id": "abc", "topics": ["live-fs-topic"] }, "timestamp": "2026-07-31T18:00:00Z" }"#,
            // disconnect envelope
            #"{ "type": "disconnect", "payload": {}, "timestamp": "2026-07-31T18:00:00Z" }"#,
            // a future/unknown event type
            #"{ "type": "reorder", "payload": {}, "timestamp": "2026-07-31T18:00:00Z" }"#,
            // no type discriminator at all
            #"{ "payload": { "source": "etl" } }"#,
            // malformed JSON
            #"{ "type": "insert", "payload": {"#,
            // not an object
            #"[]"#,
        ]
    )
    func dropsNonEventFrames(json: String) {
        #expect(decode(json) == nil)
    }

    @Test("An insert payload the converter drops (a non-track marker row) decodes to nil")
    func dropsNonTrackInsert() {
        // dj_join carries no track fields; FlowsheetConverter drops it (#693), so
        // there's no playcut to append and the event is discarded.
        let json = """
        {
          "type": "insert",
          "payload": { "id": 7, "play_order": 1, "add_time": "2026-07-31T18:00:00Z", "entry_type": "dj_join", "dj_name": "DJ Foo" },
          "timestamp": "2026-07-31T18:00:00Z"
        }
        """
        #expect(decode(json) == nil)
    }

    @Test("An insert payload missing a required wire field (id) decodes to nil, not a throw")
    func dropsInsertMissingRequiredField() {
        let json = """
        {
          "type": "insert",
          "payload": { "artist_name": "Juana Molina", "track_title": "la paradoja", "play_order": 1, "add_time": "2026-07-31T18:00:00Z", "entry_type": "track" },
          "timestamp": "2026-07-31T18:00:00Z"
        }
        """
        #expect(decode(json) == nil)
    }
}
