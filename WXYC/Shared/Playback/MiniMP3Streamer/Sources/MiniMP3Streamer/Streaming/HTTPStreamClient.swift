import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL

/// Errors that can occur during HTTP streaming
enum HTTPStreamError: Error {
    case invalidURL
    case connectionFailed
    case httpError(statusCode: Int)
    case sslError(Error)
    case timeout
    case cancelled
}

/// HTTP client for streaming audio data using SwiftNIO
final class HTTPStreamClient: @unchecked Sendable {
    private let url: URL
    private let configuration: StreamingAudioConfiguration
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private weak var delegate: (any HTTPStreamClientDelegate)?

    private let state: StateBox
    private let channelBox: ChannelBox

    init(url: URL, configuration: StreamingAudioConfiguration, delegate: any HTTPStreamClientDelegate) {
        self.url = url
        self.configuration = configuration
        self.delegate = delegate
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        self.state = StateBox()
        self.channelBox = ChannelBox()
    }

    deinit {
        disconnect()
        try? eventLoopGroup.syncShutdownGracefully()
    }

    func connect() async throws {
        guard let host = url.host else {
            throw HTTPStreamError.invalidURL
        }

        let port = url.port ?? (url.scheme == "https" ? 443 : 80)
        let useSSL = url.scheme == "https"

        state.isConnecting = true

        do {
            let bootstrap = ClientBootstrap(group: eventLoopGroup)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelInitializer { channel in
                    let handlers: [ChannelHandler]

                    if useSSL {
                        do {
                            let sslContext = try NIOSSLContext(configuration: .makeClientConfiguration())
                            let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
                            handlers = [
                                sslHandler,
                                HTTPRequestEncoder(),
                                ByteToMessageHandler(HTTPResponseDecoder()),
                                HTTPStreamHandler(client: self)
                            ]
                        } catch {
                            return channel.eventLoop.makeFailedFuture(HTTPStreamError.sslError(error))
                        }
                    } else {
                        handlers = [
                            HTTPRequestEncoder(),
                            ByteToMessageHandler(HTTPResponseDecoder()),
                            HTTPStreamHandler(client: self)
                        ]
                    }

                    return channel.pipeline.addHandlers(handlers, position: .last)
                }

            let channel = try await bootstrap.connect(host: host, port: port).get()
            channelBox.channel = channel

            // Send HTTP GET request
            var head = HTTPRequestHead(
                version: .http1_1,
                method: .GET,
                uri: url.path.isEmpty ? "/" : url.path
            )
            head.headers.add(name: "Host", value: host)
            head.headers.add(name: "User-Agent", value: "AVAudioStreamer/1.0")
            head.headers.add(name: "Accept", value: "audio/mpeg")
            head.headers.add(name: "Connection", value: "keep-alive")

            try await channel.writeAndFlush(HTTPClientRequestPart.head(head)).get()
            try await channel.writeAndFlush(HTTPClientRequestPart.end(nil)).get()

            state.isConnected = true
            state.isConnecting = false

            notifyDelegate { [weak self] in
                guard let self = self else { return }
                self.delegate?.httpStreamClientDidConnect(self)
            }
        } catch {
            state.isConnecting = false
            state.isConnected = false
            throw HTTPStreamError.connectionFailed
        }
    }

    func disconnect() {
        state.isConnected = false
        state.isConnecting = false

        if let channel = channelBox.channel {
            channelBox.channel = nil
            _ = channel.close()
        }

        notifyDelegate { [weak self] in
            guard let self = self else { return }
            self.delegate?.httpStreamClientDidDisconnect(self)
        }
    }

    fileprivate func handleData(_ data: Data) {
        guard state.isConnected else { return }

        notifyDelegate { [weak self] in
            guard let self = self else { return }
            self.delegate?.httpStreamClient(self, didReceiveData: data)
        }
    }

    fileprivate func handleError(_ error: Error) {
        notifyDelegate { [weak self] in
            guard let self = self else { return }
            self.delegate?.httpStreamClient(self, didEncounterError: error)
        }
    }

    fileprivate func handleHTTPError(statusCode: Int) {
        let error = HTTPStreamError.httpError(statusCode: statusCode)
        handleError(error)
    }

    private func notifyDelegate(_ closure: @Sendable @escaping () -> Void) {
        Task { @MainActor in
            closure()
        }
    }
}

// MARK: - Thread-safe state management

private final class StateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _isConnected = false
    private var _isConnecting = false

    var isConnected: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isConnected
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isConnected = newValue
        }
    }

    var isConnecting: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isConnecting
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isConnecting = newValue
        }
    }
}

private final class ChannelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _channel: Channel?

    var channel: Channel? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _channel
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _channel = newValue
        }
    }
}

// MARK: - HTTP Stream Handler

private final class HTTPStreamHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private weak var client: HTTPStreamClient?
    private var receivedStatusCode: Int?

    init(client: HTTPStreamClient) {
        self.client = client
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            receivedStatusCode = Int(head.status.code)
            if head.status.code != 200 {
                client?.handleHTTPError(statusCode: Int(head.status.code))
                context.close(promise: nil)
            }

        case .body(var buffer):
            guard let statusCode = receivedStatusCode, statusCode == 200 else {
                return
            }

            let length = buffer.readableBytes
            if length > 0, let bytes = buffer.readBytes(length: length) {
                let data = Data(bytes)
                client?.handleData(data)
            }

        case .end:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        client?.handleError(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        client?.disconnect()
    }
}
