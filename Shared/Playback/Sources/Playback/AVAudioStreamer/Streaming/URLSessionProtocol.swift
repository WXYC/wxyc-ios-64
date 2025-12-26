#if !os(watchOS)

import Foundation

/// Protocol abstracting URLSession for streaming with delegate callbacks
protocol StreamingSession: AnyObject, Sendable {
    /// Creates a data task for the given request
    func dataTask(with request: URLRequest) -> URLSessionDataTask

    /// Invalidates the session and cancels all tasks
    func invalidateAndCancel()
}

extension URLSession: StreamingSession {}

#endif
