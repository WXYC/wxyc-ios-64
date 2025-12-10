import Foundation

/// Delegate for HTTP stream client events
protocol HTTPStreamClientDelegate: AnyObject, Sendable {
    /// Called when data is received from the stream
    func httpStreamClient(_ client: HTTPStreamClient, didReceiveData data: Data)

    /// Called when the stream connects successfully
    func httpStreamClientDidConnect(_ client: HTTPStreamClient)

    /// Called when the stream disconnects
    func httpStreamClientDidDisconnect(_ client: HTTPStreamClient)

    /// Called when an error occurs
    func httpStreamClient(_ client: HTTPStreamClient, didEncounterError error: Error)
}
