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
final class HTTPStreamClient: @unchecked Sendable {
    private let url: URL
    private let configuration: MiniMP3StreamerConfiguration
    private weak var delegate: (any HTTPStreamClientDelegate)?

    private let streamingTask: StreamingTaskBox

    /// Chunk size for buffering bytes before forwarding to delegate
    private static let chunkSize = 4096

    init(url: URL, configuration: MiniMP3StreamerConfiguration, delegate: any HTTPStreamClientDelegate) {
        self.url = url
        self.configuration = configuration
        self.delegate = delegate
        self.streamingTask = StreamingTaskBox()
    }

    func connect() async throws {
        // Cancel any existing connection
        streamingTask.task?.cancel()

        var request = URLRequest(url: url)
        request.setValue("MiniMP3Streamer/1.0", forHTTPHeaderField: "User-Agent")
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

            // Notify delegate of successful connection
            notifyDelegate { [weak self] in
                guard let self else { return }
                self.delegate?.httpStreamClientDidConnect(self)
            }

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

                            self.notifyDelegate { [weak self] in
                                guard let self else { return }
                                self.delegate?.httpStreamClient(self, didReceiveData: chunk)
                            }
                        }
                    }

                    // Flush remaining buffer
                    if !buffer.isEmpty {
                        let chunk = buffer
                        self.notifyDelegate { [weak self] in
                            guard let self else { return }
                            self.delegate?.httpStreamClient(self, didReceiveData: chunk)
                        }
                    }

                    // Stream ended normally
                    self.notifyDelegate { [weak self] in
                        guard let self else { return }
                        self.delegate?.httpStreamClientDidDisconnect(self)
                    }
                } catch {
                    if !Task.isCancelled {
                        self.notifyDelegate { [weak self] in
                            guard let self else { return }
                            self.delegate?.httpStreamClient(self, didEncounterError: error)
                        }
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

        notifyDelegate { [weak self] in
            guard let self else { return }
            self.delegate?.httpStreamClientDidDisconnect(self)
        }
    }

    private func notifyDelegate(_ closure: @Sendable @escaping () -> Void) {
        Task { @MainActor in
            closure()
        }
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
