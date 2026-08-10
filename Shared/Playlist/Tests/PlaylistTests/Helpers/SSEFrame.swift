//
//  SSEFrame.swift
//  Playlist
//
//  Builds the `live-fs-topic` frame envelope for transport and parity tests,
//  so the {type, payload, timestamp} shape exists in one place and a
//  frame-contract change is one edit. LiveFsEventDecodingTests deliberately
//  does NOT use this: its inline JSON pins the raw wire contract, envelope
//  included, independent of any Swift-side builder.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

enum SSEFrame {
    /// One frame's JSON — the `{type, payload, timestamp}` envelope Backend
    /// emits on `live-fs-topic`, with `payloadJSON` spliced in verbatim.
    static func json(
        type: String,
        payloadJSON: String,
        timestamp: String = "2026-07-31T18:00:00Z"
    ) -> String {
        #"{"type":"\#(type)","payload":\#(payloadJSON),"timestamp":"\#(timestamp)"}"#
    }
}
