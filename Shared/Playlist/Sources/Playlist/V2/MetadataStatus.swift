//
//  MetadataStatus.swift
//  Playlist
//
//  Wire-format enum for the v2 flowsheet row's `metadata_status` field.
//  Source-of-truth definition is Backend-Service's `metadata_status_enum`
//  Postgres type — see https://github.com/WXYC/Backend-Service/issues/891.
//
//  Created by Jake Bromberg on 05/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Enrichment state for a v2 flowsheet track row.
///
/// Raw values match Backend's `metadata_status` Postgres enum exactly. Lives
/// in the `Playlist` package (alongside `FlowsheetEntry`) rather than in
/// `Metadata` because `Metadata` depends on `Playlist`; placing the enum
/// in `Metadata` would create a circular dep.
///
/// Consumers branch on this in two ways:
/// - `pending` / `enriching` → enrichment is still in flight; fall back to
///   `PlaycutMetadataService.fetchMetadata` for the playcut detail view.
/// - `enrichedMatch` / `enrichedNoMatch` / `failedNoRetry` → render directly
///   from the inline `FlowsheetEntry` fields. No outbound proxy request.
///
/// See https://github.com/WXYC/wxyc-ios-64/issues/270 for the consumer logic.
public enum MetadataStatus: String, Codable, Sendable, Equatable {
    /// Row inserted; no enrichment attempt yet, OR a transient failure left
    /// the row eligible for retry.
    case pending

    /// A consumer instance has claimed this row and is mid-LML-call. Set when
    /// status flips from `pending` to `enriching` (per Epic C's C2 consumer
    /// claim/race pattern in BS#892).
    case enriching

    /// LML returned full Discogs metadata; all populated fields on the row
    /// are authoritative.
    case enrichedMatch = "enriched_match"

    /// LML succeeded but found no Discogs match for this row. Only the
    /// synthesized YouTube/Bandcamp/SoundCloud search URLs are populated.
    case enrichedNoMatch = "enriched_no_match"

    /// Enrichment exceeded the retry budget; row is terminal. Operationally
    /// distinct from `pending`: the recurring drift-repair cron skips
    /// `failedNoRetry` rows and they require manual triage.
    case failedNoRetry = "failed_no_retry"
}
