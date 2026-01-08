import Foundation

/// Errors that can occur during HTTP streaming
enum HTTPStreamError: Error {
    case invalidURL
    case connectionFailed
    case httpError(statusCode: Int)
    case timeout
    case cancelled
}

/// HTTP client for streaming audio data using URLSession
final class HTTPStreamClient: HTTPStreamClientProtocol, @unchecked Sendable {
    private let url: URL
    private let configuration: AVAudioStreamerConfiguration
    private let streamingTask: StreamingTaskBox
    private let continuation: AsyncStream<HTTPStreamEvent>.Continuation

    let eventStream: AsyncStream<HTTPStreamEvent>

    /// Chunk size for buffering bytes before forwarding
    private static let chunkSize = 4096

    init(url: URL, configuration: AVAudioStreamerConfiguration) {
        self.url = url
        self.configuration = configuration
        self.streamingTask = StreamingTaskBox()

        var cont: AsyncStream<HTTPStreamEvent>.Continuation!
        self.eventStream = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
    }

    func connect() async throws {
        // Cancel any existing connection
        streamingTask.task?.cancel()

        var request = URLRequest(url: url)
        request.setValue("AVAudioStreamer/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.timeoutInterval = configuration.connectionTimeout

        let session = URLSession.shared

        do {
            let (bytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPStreamError.connectionFailed
            }

            guard httpResponse.statusCode == 200 else {
                throw HTTPStreamError.httpError(statusCode: httpResponse.statusCode)
            }

            // Notify of successful connection
            continuation.yield(.connected)

            // Start streaming task
            let task = Task { [weak self] in
                guard let self else { return }

                var buffer = Data()
                buffer.reserveCapacity(Self.chunkSize)

                do {
                    for try await byte in bytes {
                        if Task.isCancelled { break }

                        buffer.append(byte)

                        if buffer.count >= Self.chunkSize {
                            let chunk = buffer
                            buffer.removeAll(keepingCapacity: true)
                            self.continuation.yield(.data(chunk))
                        }
                    }

                    // Flush remaining buffer
                    if !buffer.isEmpty {
                        self.continuation.yield(.data(buffer))
                    }

                    // Stream ended normally
                    self.continuation.yield(.disconnected)
                } catch {
                    if !Task.isCancelled {
                        self.continuation.yield(.error(error))
                    }
                }
            }

            streamingTask.task = task

        } catch {
            if error is CancellationError {
                throw HTTPStreamError.cancelled
            }
            throw error
        }
    }

    func disconnect() {
        streamingTask.task?.cancel()
        streamingTask.task = nil
        continuation.yield(.disconnected)
    }
}

// MARK: - Thread-safe task storage

private final class StreamingTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: Task<Void, Never>?

    var task: Task<Void, Never>? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _task
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _task = newValue
        }
    }
}
