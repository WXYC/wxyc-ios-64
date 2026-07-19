//
//  FlowsheetEntry.swift
//  Playlist
//
//  Raw response model for API v2 flowsheet entries.
//
//  Created by Jake Bromberg on 01/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import Foundation

/// Wrapper for the v2 flowsheet API response, which nests entries under an `"entries"` key.
///
/// Also carries the top-level `on_air` field as a tri-state ``OnAir``. `CodingKeys`
/// alone can't distinguish a JSON `null` from a missing key, so the on-air state is
/// decoded by key presence: absent → ``OnAir/unknown``, explicit `null` →
/// ``OnAir/automation``, an object with `dj_name` → ``OnAir/dj(_:)``.
struct FlowsheetResponse: Codable, Sendable {
    let entries: [FlowsheetEntry]
    let onAir: OnAir

    private enum CodingKeys: String, CodingKey {
        case entries
        case onAir = "on_air"
    }

    /// Minimal decode shape for the `on_air` object (`{ "dj_name": "..." }`).
    private struct OnAirInfo: Codable {
        let dj_name: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decode([FlowsheetEntry].self, forKey: .entries)

        if !container.contains(.onAir) {
            // Field absent: older backend, v1, or a non-default query branch.
            onAir = .unknown
        } else if try container.decodeNil(forKey: .onAir) {
            // Explicit JSON null: confirmed automation.
            onAir = .automation
        } else if let info = try? container.decode(OnAirInfo.self, forKey: .onAir),
                  case let djName = info.dj_name.trimmingCharacters(in: .whitespacesAndNewlines),
                  !djName.isEmpty {
            onAir = .dj(djName)
        } else {
            // `on_air` is present but not a usable named-DJ object — a malformed
            // shape (wrong type, missing/empty `dj_name`). Degrade to `.unknown`
            // rather than throwing: a throw here would fail the whole
            // FlowsheetResponse decode and freeze every now-playing update over a
            // cosmetic auxiliary field. This mirrors the tolerant decoding of the
            // other optional v2 fields (see `metadataStatus`).
            onAir = .unknown
        }
    }
}

/// Raw response model for a single entry from the v2 flowsheet API.
///
/// Entry type is determined by the `entry_type` field (`"track"`, `"talkset"`,
/// `"breakpoint"`, `"show_start"`, `"show_end"`). The older `message`-based
/// detection is used as a fallback when `entry_type` is absent.
struct FlowsheetEntry: Codable, Sendable {
    let id: Int
    let show_id: Int?
    let album_id: Int?
    let artist_name: String?
    let album_title: String?
    let track_title: String?
    let record_label: String?
    let rotation_id: Int?
    let rotation_play_freq: String?
    let request_flag: Bool?
    let message: String?
    let play_order: Int
    let add_time: String

    /// Explicit entry type from the v2 API (e.g. `"track"`, `"talkset"`, `"breakpoint"`,
    /// `"show_start"`, `"show_end"`). `nil` when decoding older response formats.
    var entry_type: String? = nil

    /// Exact top-of-the-hour for a breakpoint marker (ISO 8601, same format as
    /// `add_time`). The breakpoint's `add_time` is its logging instant — typically
    /// ~1 min before the hour — so flooring it to an hour label renders one hour
    /// early. `radio_hour` carries the real top-of-hour. Optional on the wire:
    /// older servers omit it, so consumers fall back to `add_time`. See ios#404.
    var radio_hour: String? = nil

    /// DJ name for show start/end markers. Present only in v2 responses.
    var dj_name: String? = nil

    /// Resolved catalog artist id (`library.artist_id` → the `artists.id`
    /// keyspace shared with `Concert.headlining_artist_id`). Additive and
    /// nullable on the wire (api.yaml 1.19.0, BS#1625): free-text rows
    /// (`album_id` null) and feeds that predate the field decode as `nil`.
    var artist_id: Int? = nil

    // Metadata fields from album_metadata/artist_metadata LEFT JOINs.
    // Present only in v2 responses after backend enrichment completes.
    // Defaults to nil so existing test constructors remain valid.
    var artwork_url: String? = nil
    var discogs_url: String? = nil
    var release_year: Int? = nil
    var spotify_url: String? = nil
    var apple_music_url: String? = nil
    var youtube_music_url: String? = nil
    var bandcamp_url: String? = nil
    var soundcloud_url: String? = nil
    var artist_bio: String? = nil
    var artist_wikipedia_url: String? = nil

    /// Discogs genre classifications for the release. Present only in v2
    /// responses once the backend emits them; decodes as `nil` until then.
    var genres: [String]? = nil

    /// Discogs style classifications (more specific than genres). Present only
    /// in v2 responses once the backend emits them; decodes as `nil` until then.
    var styles: [String]? = nil

    /// Raw enrichment-state string from the wire. Read via `metadataStatus`
    /// for the typed accessor; the raw string is preserved so an older iOS
    /// build that sees a future state can surface it diagnostically without
    /// failing the row decode.
    var metadata_status: String? = nil

    /// An upcoming Triangle-area show for this track's artist, embedded by
    /// Backend-Service when the resolved artist matches a curated upcoming
    /// concert. Present only on the enriched v2 feed; decodes to `nil` on older
    /// feeds. Carried straight through to ``Playcut/upcomingShow`` by
    /// `FlowsheetConverter` (which reads `upcoming_show?.concert`). Wrapped in
    /// ``TolerantConcert`` so a present-but-malformed embed degrades to `nil`
    /// instead of throwing — see that type's doc comment.
    var upcoming_show: TolerantConcert? = nil
}

/// Decodes an embedded `Concert` tolerantly: a present-but-malformed embed
/// (a missing required sub-field from a backend join regression) becomes `nil`
/// instead of throwing and failing the whole atomic `[FlowsheetEntry]` decode —
/// the same degrade-don't-throw discipline as `FlowsheetResponse.onAir`.
///
/// The field rides `FlowsheetEntry`'s synthesized `Codable`, whose
/// `decodeIfPresent` already maps an absent/null `upcoming_show` to `nil`. This
/// wrapper adds the third case: a present object routes through
/// ``init(from:)``'s `try?`, so a malformed object also becomes `nil` rather
/// than propagating the throw up through the synthesized entry decode. Using a
/// wrapper keeps `FlowsheetEntry`'s memberwise init (which the tests rely on)
/// and avoids a hand-written `init(from:)` that would be a drift trap across the
/// entry's ~28 fields.
struct TolerantConcert: Codable, Sendable, Equatable {
    let concert: Concert?

    init(concert: Concert?) { self.concert = concert }

    init(from decoder: Decoder) throws { concert = try? Concert(from: decoder) }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let concert {
            try container.encode(concert)
        } else {
            try container.encodeNil()
        }
    }
}

extension FlowsheetEntry {
    /// Typed accessor for `metadata_status`. Returns `nil` when the field
    /// is absent OR carries an unrecognized value — the consumer (#270)
    /// treats both as "fall back to the proxy-fetch path," which is the
    /// safe default for forward-compat with future Backend enum extensions.
    var metadataStatus: MetadataStatus? {
        metadata_status.flatMap(MetadataStatus.init(rawValue:))
    }
}

