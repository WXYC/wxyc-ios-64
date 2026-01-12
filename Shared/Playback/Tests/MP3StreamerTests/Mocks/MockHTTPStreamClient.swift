import Foundation
@testable import MP3StreamerModule

#if !os(watchOS)

/// Mock HTTP stream client that feeds test data instantly without network access
final class MockHTTPStreamClient: HTTPStreamClientProtocol, @unchecked Sendable {
    private let continuation: AsyncStream<HTTPStreamEvent>.Continuation
    let eventStream: AsyncStream<HTTPStreamEvent>

    /// Optional test data to feed when connect() is called
    var testData: Data?

    /// Chunk size for splitting test data
    var chunkSize: Int = 4096

    /// Whether connect should succeed
    var shouldSucceed = true

    /// Error to throw if shouldSucceed is false
    var errorToThrow: Error = HTTPStreamError.connectionFailed

    /// Track whether connect was called
    private(set) var connectCallCount = 0

    /// Track whether disconnect was called
    private(set) var disconnectCallCount = 0

    init() {
        var cont: AsyncStream<HTTPStreamEvent>.Continuation!
        self.eventStream = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
    }

    func connect() async throws {
        connectCallCount += 1

        guard shouldSucceed else {
            throw errorToThrow
        }

        // Emit connected event
        continuation.yield(.connected)

        // Feed test data in chunks if available
        if let data = testData {
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                let chunk = data[offset..<end]
                continuation.yield(.data(Data(chunk)))
                offset = end
            }
        }
    }

    func disconnect() {
        disconnectCallCount += 1
        continuation.yield(.disconnected)
    }

    // MARK: - Test Helpers

    /// Manually yield an event for testing
    func yield(_ event: HTTPStreamEvent) {
        continuation.yield(event)
    }

    /// Finish the stream
    func finish() {
        continuation.finish()
    }
}

#endif
