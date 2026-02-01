//
//  HTTPStreamClient.swift
//  Playback
//
//  HTTP streaming client for continuous audio data download.
//
//  Created by Jake Bromberg on 12/07/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Logger

/// Errors that can occur during HTTP streaming
enum HTTPStreamError: Error {
    case invalidURL
    case connectionFailed
    case httpError(statusCode: Int)
    case timeout
    case cancelled
}

/// HTTP client for streaming audio data using URLSession with delegate-based chunked data reception.
/// This approach receives data in OS-sized chunks (typically 16KB-64KB) rather than byte-by-byte,
/// significantly reducing async overhead for streaming scenarios.
final class HTTPStreamClient: HTTPStreamClientProtocol, @unchecked Sendable {
    private let url: URL
    private let configuration: MP3StreamerConfiguration
    private let continuation: AsyncStream<HTTPStreamEvent>.Continuation
    private let sessionState: SessionStateBox

    let eventStream: AsyncStream<HTTPStreamEvent>

    init(url: URL, configuration: MP3StreamerConfiguration) {
        self.url = url
        self.configuration = configuration
        self.sessionState = SessionStateBox()

        // Use bounded buffering - HTTP events should be consumed quickly
        // but we allow some slack for reconnection scenarios
        var cont: AsyncStream<HTTPStreamEvent>.Continuation!
        self.eventStream = AsyncStream(bufferingPolicy: .bufferingOldest(64)) { cont = $0 }
        self.continuation = cont
    }

    func connect() async throws {
        Log(.info, category: .playback, "Connecting to \(url.absoluteString)")
        // Cancel any existing connection
        sessionState.invalidateSession()

        var request = URLRequest(url: url)
        request.setValue("MP3Streamer/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.timeoutInterval = configuration.connectionTimeout

        // Create delegate that receives data in chunks
        let delegate = StreamingDataDelegate(continuation: continuation)

        // Create session with delegate - data arrives in chunks via delegate methods
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.connectionTimeout
        sessionConfig.timeoutIntervalForResource = 0 // No timeout for streaming
        sessionConfig.waitsForConnectivity = false

        let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        let dataTask = session.dataTask(with: request)

        sessionState.setSession(session, task: dataTask)
        dataTask.resume()
    }

    func disconnect() {
        Log(.info, category: .playback, "Disconnected (intentional)")
        sessionState.invalidateSession()
        continuation.yield(.disconnected)
    }
}

// MARK: - URLSession Delegate for Chunked Data Reception

/// Delegate that receives streaming data in OS-sized chunks rather than byte-by-byte.
/// This dramatically reduces CPU overhead compared to AsyncBytes iteration.
private final class StreamingDataDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let continuation: AsyncStream<HTTPStreamEvent>.Continuation
    private var hasConnected = false

    init(continuation: AsyncStream<HTTPStreamEvent>.Continuation) {
        self.continuation = continuation
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            Log(.error, category: .playback, "Connection failed: invalid response type")
            continuation.yield(.error(HTTPStreamError.connectionFailed))
            completionHandler(.cancel)
            return
        }

        guard httpResponse.statusCode == 200 else {
            Log(.error, category: .playback, "HTTP error: status code \(httpResponse.statusCode)")
            continuation.yield(.error(HTTPStreamError.httpError(statusCode: httpResponse.statusCode)))
            completionHandler(.cancel)
            return
        }

        // Successfully connected
        Log(.info, category: .playback, "Connected (HTTP \(httpResponse.statusCode))")
        hasConnected = true
        continuation.yield(.connected)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Data arrives in chunks (typically 16KB-64KB from the network stack)
        // No per-byte async overhead - this is the key optimization
        continuation.yield(.data(data))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            // Check if this was a cancellation
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                // Don't yield error for intentional cancellation
                return
            }
            Log(.error, category: .playback, "Connection error: \(error.localizedDescription)")
            continuation.yield(.error(error))
        } else if hasConnected {
            // Stream ended normally
            Log(.info, category: .playback, "Stream ended (server closed connection)")
            continuation.yield(.disconnected)
        }
    }
}

// MARK: - Thread-safe session storage

private final class SessionStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _session: URLSession?
    private var _task: URLSessionDataTask?

    func setSession(_ session: URLSession, task: URLSessionDataTask) {
        lock.lock()
        defer { lock.unlock() }
        _session = session
        _task = task
    }

    func invalidateSession() {
        lock.lock()
        let session = _session
        let task = _task
        _session = nil
        _task = nil
        lock.unlock()

        task?.cancel()
        session?.invalidateAndCancel()
    }
}
