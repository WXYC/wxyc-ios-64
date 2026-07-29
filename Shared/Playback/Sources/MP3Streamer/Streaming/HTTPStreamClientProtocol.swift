//
//  HTTPStreamClientProtocol.swift
//  Playback
//
//  Protocol for HTTP streaming client abstraction.
//
//  Created by Jake Bromberg on 01/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

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
    /// The underlying task is parked waiting for network connectivity — offline,
    /// mid-handover, or otherwise unable to reach the host right now.
    /// `URLSession` delivers this instead of failing outright when
    /// `waitsForConnectivity` is enabled; the task stays alive and resumes on
    /// its own once a route appears, so this is a distinct "still trying"
    /// signal, not a failure. See WXYC/wxyc-ios-64#697.
    case waitingForConnectivity
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
