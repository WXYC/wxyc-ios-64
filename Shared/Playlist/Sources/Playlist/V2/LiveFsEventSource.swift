//
//  LiveFsEventSource.swift
//  Playlist
//
//  Transport for Backend-Service's `live-fs-topic` server-sent-events stream:
//  a protocol seam (`LiveFsEventSource`) so `PlaylistService` can be tested
//  against a scripted source, the URLSession-backed production implementation
//  (`FlowsheetLiveEventSource`), and the `text/event-stream` frame accumulator
//  (`SSEFrameAccumulator`) that reassembles `data:` frames from the raw response
//  bytes. See WXYC/wxyc-ios-64#269 and #780.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger

/// A source of decoded `live-fs-topic` events.
///
/// One call to ``connect()`` models a single connection attempt: it yields
/// decoded events until the stream ends (the connection drops, errors, or is
/// cancelled), at which point the `AsyncStream` finishes. Reconnection with
/// backoff is the consumer's responsibility (`PlaylistService`), which keeps
/// the transport a thin single-connection wrapper and the reconnect policy
/// unit-testable in isolation.
public protocol LiveFsEventSource: Sendable {
    /// Opens one connection and yields decoded events until it ends.
    func connect() -> AsyncStream<LiveFsEvent>
}

/// Production `LiveFsEventSource`: streams `GET /events/stream?topics=live-fs-topic`
/// over `URLSession.bytes`, reassembles `data:` frames, and decodes each into a
/// `LiveFsEvent`. The topic is public (`security: []` in the contract), so no
/// auth header is attached.
public final class FlowsheetLiveEventSource: LiveFsEventSource, @unchecked Sendable {
    /// The public SSE endpoint, subscribed to the anonymous `live-fs-topic`.
    public static let defaultURL = URL(string: "https://api.wxyc.org/events/stream?topics=live-fs-topic")!

    private let url: URL
    private let session: URLSession

    public init(url: URL = FlowsheetLiveEventSource.defaultURL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    public func connect() -> AsyncStream<LiveFsEvent> {
        AsyncStream { continuation in
            let task = Task { [url, session] in
                do {
                    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                    // The 30 s server heartbeat (`: keepalive`) resets the
                    // session's default 60 s between-packet timeout, so a live
                    // connection stays open; if heartbeats stop, the request
                    // errors within ~60 s and the consumer reconnects.
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        Log(.warning, category: .network, "live-fs SSE connect returned non-2xx; will reconnect")
                        continuation.finish()
                        return
                    }

                    var accumulator = SSEFrameAccumulator()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        guard let frame = accumulator.consume(byte: byte) else { continue }
                        if let event = LiveFsEvent(frameData: frame) {
                            continuation.yield(event)
                        }
                    }
                } catch is CancellationError {
                    // Foregrounded -> backgrounded: expected teardown, silent.
                } catch {
                    // Network error or EOF — the consumer reconnects with backoff.
                    Log(.info, category: .network, "live-fs SSE stream ended: \(error.localizedDescription)")
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Reassembles `text/event-stream` `data:` frames from the raw response bytes.
///
/// An SSE frame is one or more `data:` lines terminated by a blank line;
/// multiple `data:` lines within a frame concatenate with `\n`. Comment lines
/// (`: keepalive` heartbeats) and the other SSE fields (`event:`, `id:`,
/// `retry:`) are ignored — this consumer only cares about the JSON `data:`
/// payload. Kept as a synchronous value type so the framing logic is testable
/// without a live socket.
///
/// The transport feeds ``consume(byte:)``, which splits lines itself and hands
/// them to ``consume(line:)``. Splitting here rather than upstream is
/// load-bearing, not stylistic — see ``consume(byte:)``.
struct SSEFrameAccumulator {
    private var dataLines: [String] = []
    private var lineBytes: [UInt8] = []
    /// Whether the previous byte was a CR, so the LF of a CRLF pair is swallowed
    /// rather than ending a second, spurious (and frame-terminating) empty line.
    private var pendingCR = false

    /// Feeds one byte of the response body. Returns the completed frame's JSON
    /// bytes when that byte terminated the blank line ending a frame, otherwise
    /// `nil`.
    ///
    /// Framing has to happen at the byte level: `AsyncLineSequence` (the
    /// `bytes.lines` this transport used through #269) never yields an empty
    /// element, so the blank lines SSE uses as frame terminators vanished before
    /// reaching ``consume(line:)`` and no frame was ever completed — a stream
    /// that returned HTTP 200 and delivered bytes forever while yielding zero
    /// events.
    ///
    /// All three line terminators the SSE spec allows — LF, CRLF, and a lone CR —
    /// end a line here.
    mutating func consume(byte: UInt8) -> Data? {
        switch byte {
        case UInt8(ascii: "\r"):
            pendingCR = true
            return flushLine()
        case UInt8(ascii: "\n"):
            guard !pendingCR else {
                pendingCR = false
                return nil
            }
            return flushLine()
        default:
            pendingCR = false
            lineBytes.append(byte)
            return nil
        }
    }

    /// Ends the buffered line and feeds it to ``consume(line:)``.
    private mutating func flushLine() -> Data? {
        let line = String(decoding: lineBytes, as: UTF8.self)
        lineBytes.removeAll(keepingCapacity: true)
        return consume(line: line)
    }

    /// Feeds one newline-stripped line. Returns the completed frame's JSON bytes
    /// when `line` is the blank line terminating a frame that carried at least
    /// one `data:` line; otherwise `nil`.
    mutating func consume(line: String) -> Data? {
        guard !line.isEmpty else {
            guard !dataLines.isEmpty else { return nil }
            let joined = dataLines.joined(separator: "\n")
            dataLines.removeAll(keepingCapacity: true)
            return Data(joined.utf8)
        }

        if let content = Self.dataFieldContent(of: line) {
            dataLines.append(content)
        }
        // Comment lines (":...") and non-`data` fields are ignored.
        return nil
    }

    /// Extracts the value of a `data:` field line, stripping the single optional
    /// leading space the SSE spec allows after the colon. Returns `nil` for a
    /// line that isn't a `data:` field.
    private static func dataFieldContent(of line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let rest = line.dropFirst("data:".count)
        return rest.hasPrefix(" ") ? String(rest.dropFirst()) : String(rest)
    }
}
