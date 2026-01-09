import Foundation

/// Protocol for providing the current time, enabling testable time-dependent code.
public protocol Clock: Sendable {
    /// The current time as a TimeInterval since the reference date.
    var now: TimeInterval { get }
}

/// Default clock implementation that uses the system time.
public struct SystemClock: Clock, Sendable {
    public init() {}

    public var now: TimeInterval {
        Date.timeIntervalSinceReferenceDate
    }
}
