import Foundation

/// Events emitted by an HTTP stream client
public enum HTTPStreamEvent: Sendable {
    /// Successfully connected to the stream
    case connected
    /// Received a chunk of data
    case data(Data)
    /// Disconnected from the stream
    case disconnected
    /// An error occurred
    case error(Error)
}

/// Protocol for HTTP stream clients, enabling dependency injection for testing
public protocol HTTPStreamClientProtocol: Sendable {
    /// Stream of events from the HTTP connection
    var eventStream: AsyncStream<HTTPStreamEvent> { get }

    /// Connect to the stream and begin receiving data
    func connect() async throws

    /// Disconnect from the stream
    func disconnect()
}
