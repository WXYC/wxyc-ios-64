//
//  LiveFsEvent.swift
//  Playlist
//
//  Domain model for a decoded event from Backend-Service's `live-fs-topic`
//  server-sent-events stream (`GET /events/stream?topics=live-fs-topic`).
//  Reuses the tolerant `FlowsheetEntry` wire decoder for the row payloads and
//  the shared `FlowsheetConverter` mapping, so an SSE-pushed row becomes the
//  exact same `Playcut` a polled row would. See WXYC/wxyc-ios-64#269.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

/// A decoded event from the Backend `live-fs-topic` SSE stream.
///
/// The contract (`LiveFsEvent`, wxyc-shared `api.yaml`) is a discriminated
/// union on a `type` field, every frame sharing a `{ type, payload, timestamp }`
/// envelope. Only the three real event types are modeled here; the stream's
/// own envelope frames (`connection-established`, `subscription`), the
/// `: keepalive` heartbeat comment, and any future/unknown `type` decode to
/// `nil` (see ``init(frameData:decoder:)``) and are dropped by the consumer —
/// the same degrade-don't-throw discipline the flowsheet decoder uses.
///
/// The row-bearing cases carry a fully-mapped ``Playcut`` rather than the raw
/// internal `FlowsheetEntry`, keeping the wire type module-private while
/// letting the app target (and `PlaylistTesting`) construct and match events.
/// Both `insert` and `update` payloads are the contract's
/// `FlowsheetEntryResponse` — identical in shape to one `/flowsheet` entry —
/// and Backend only emits them for `entry_type: "track"` rows, so the decode
/// always yields a playcut.
public enum LiveFsEvent: Sendable {
    /// A brand-new flowsheet row was just created (`type: "insert"`, BS#1888),
    /// before enrichment runs — its `metadataStatus` is `.pending` and the
    /// enrichment fields are still nil. The consumer appends it immediately.
    case insert(Playcut)

    /// An existing row's metadata was finalized (`type: "update"`, BS#892). The
    /// payload is the full post-enrichment row; the consumer replaces the row
    /// with the matching `id`.
    case update(Playcut)

    /// A coarse "your view is stale, refetch" signal (`type: "refetch"`) emitted
    /// on bulk state changes (ETL runs, migrations). `source` is a free-text
    /// telemetry label the consumer must not branch on. The consumer responds
    /// with a full reconciliation fetch.
    case refetch(source: String)
}

extension LiveFsEvent {
    /// Decodes one SSE `data:` frame's JSON into a `LiveFsEvent`, or `nil` when
    /// the frame is not one of the three modeled event types — an envelope frame
    /// (`connection-established`, `subscription`, `disconnect`), a future/unknown
    /// `type`, or a payload that fails to decode or carries no renderable track
    /// row. Never throws: a malformed frame is dropped, not surfaced, so one bad
    /// frame can't tear down the stream.
    init?(frameData: Data, decoder: JSONDecoder = .shared) {
        guard let type = (try? decoder.decode(TypeEnvelope.self, from: frameData))?.type else {
            return nil
        }

        switch type {
        case "insert":
            guard let playcut = Self.decodePlaycut(from: frameData, decoder: decoder) else { return nil }
            self = .insert(playcut)
        case "update":
            guard let playcut = Self.decodePlaycut(from: frameData, decoder: decoder) else { return nil }
            self = .update(playcut)
        case "refetch":
            guard let source = (try? decoder.decode(RefetchEnvelope.self, from: frameData))?.payload.source else {
                return nil
            }
            self = .refetch(source: source)
        default:
            // connection-established, subscription, disconnect, or a future type
            // this build doesn't model — dropped, exactly like an unrecognized
            // flowsheet `entry_type`.
            return nil
        }
    }

    /// Decodes the `payload` as a `FlowsheetEntry` and maps it through the shared
    /// `FlowsheetConverter` so the SSE row gets the identical playcut mapping
    /// (HTML-decoding, inline metadata, rotation flag) as a polled row. Returns
    /// `nil` for a payload the converter drops (a non-track row — BS only emits
    /// `insert`/`update` for tracks, so this is a defensive guard, not a normal
    /// path).
    private static func decodePlaycut(from data: Data, decoder: JSONDecoder) -> Playcut? {
        guard let entry = (try? decoder.decode(EntryEnvelope.self, from: data))?.payload else {
            return nil
        }
        return FlowsheetConverter.convert([entry]).playcuts.first
    }

    /// Minimal decode shape reading only the discriminator so the payload is
    /// decoded once, against the right type, on the second pass.
    private struct TypeEnvelope: Decodable {
        let type: String
    }

    /// Envelope for the row-bearing events (`insert`/`update`), whose `payload`
    /// is a `FlowsheetEntryResponse` — the same wire shape as one `/flowsheet`
    /// entry, decoded by the existing tolerant `FlowsheetEntry`.
    private struct EntryEnvelope: Decodable {
        let payload: FlowsheetEntry
    }

    /// Envelope for `refetch`, whose `payload` is a `{ source }` telemetry object.
    private struct RefetchEnvelope: Decodable {
        struct Payload: Decodable {
            let source: String
        }
        let payload: Payload
    }
}
