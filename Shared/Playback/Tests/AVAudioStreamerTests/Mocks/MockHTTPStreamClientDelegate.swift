import Foundation
@testable import AVAudioStreamer

#if !os(watchOS)

/// Events that can be emitted by HTTPStreamClient via its delegate
enum HTTPStreamEvent: Sendable {
    case didConnect
    case didDisconnect
    case didReceiveData(Data)
    case didEncounterError(String)
}

/// Mock delegate for HTTPStreamClient that captures events via AsyncStream
final class MockHTTPStreamClientDelegate: HTTPStreamClientDelegate, @unchecked Sendable {
    private let eventContinuation: AsyncStream<HTTPStreamEvent>.Continuation
    let eventStream: AsyncStream<HTTPStreamEvent>

    /// Total bytes received across all data events
    private(set) var totalBytesReceived: Int = 0

    init() {
        var continuation: AsyncStream<HTTPStreamEvent>.Continuation!
        eventStream = AsyncStream { continuation = $0 }
        eventContinuation = continuation
    }

    deinit {
        eventContinuation.finish()
    }

    func httpStreamClient(_ client: HTTPStreamClient, didReceiveData data: Data) {
        totalBytesReceived += data.count
        eventContinuation.yield(.didReceiveData(data))
    }

    func httpStreamClientDidConnect(_ client: HTTPStreamClient) {
        eventContinuation.yield(.didConnect)
    }

    func httpStreamClientDidDisconnect(_ client: HTTPStreamClient) {
        eventContinuation.yield(.didDisconnect)
    }

    func httpStreamClient(_ client: HTTPStreamClient, didEncounterError error: Error) {
        eventContinuation.yield(.didEncounterError(error.localizedDescription))
    }
}

#endif
