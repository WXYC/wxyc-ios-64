import Testing
import Foundation
@testable import AVAudioStreamerModule

#if !os(watchOS)

@Suite("HTTPStreamClient Tests")
@MainActor
struct HTTPStreamClientTests {

    // MARK: - Test Helpers

    private func makeTestURL() -> URL {
        URL(string: "https://example.com/stream.mp3")!
    }

    private func makeConfiguration(url: URL? = nil) -> AVAudioStreamerConfiguration {
        AVAudioStreamerConfiguration(
            url: url ?? makeTestURL(),
            connectionTimeout: 5.0
        )
    }

    // MARK: - Unit Tests

    @Test("Client can be initialized")
    func testInitialization() {
        let url = makeTestURL()
        let delegate = MockHTTPStreamClientDelegate()

        let client = HTTPStreamClient(
            url: url,
            configuration: makeConfiguration(url: url),
            delegate: delegate
        )

        // Client should be created without error
        _ = client
    }

    @Test("HTTPStreamError cases are distinct")
    func testErrorCases() {
        let invalidURL = HTTPStreamError.invalidURL
        let connectionFailed = HTTPStreamError.connectionFailed
        let httpError = HTTPStreamError.httpError(statusCode: 404)
        let timeout = HTTPStreamError.timeout
        let cancelled = HTTPStreamError.cancelled

        // Verify error cases exist and are usable
        #expect(String(describing: invalidURL).contains("invalidURL"))
        #expect(String(describing: connectionFailed).contains("connectionFailed"))
        #expect(String(describing: httpError).contains("404"))
        #expect(String(describing: timeout).contains("timeout"))
        #expect(String(describing: cancelled).contains("cancelled"))
    }
}

#endif
