//
//  Observations.swift
//  Core
//
//  Created by Jake Bromberg on 12/12/25.
//

import Foundation
import Observation

/// A backport of the `Observations` struct for older OS versions.
/// It provides an `AsyncSequence` interface for observing changes to `@Observable` properties.
public struct Observations<Element: Sendable>: AsyncSequence {
    public typealias Iterator = AsyncStream<Element>.Iterator
    
    private let stream: AsyncStream<Element>?
    
    public init(
        _ apply: @escaping @MainActor @Sendable () -> Element
    ) {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
           // On newer OS versions, this struct shouldn't ideally be used if the system one is available.
           // However, if we are shadowing it, we need our own implementation or a wrapper.
           // Since we can't easily alias based on availability at compile time for the type itself in this way,
           // we will provide our implementation which works on all versions.
           // It uses withObservationTracking which is the underlying mechanism.
           self.stream = Self.createStream(apply)
        } else {
           self.stream = Self.createStream(apply)
        }
    }

    public func makeAsyncIterator() -> Iterator {
        stream?.makeAsyncIterator() ?? AsyncStream { _ in }.makeAsyncIterator()
    }

    private static func createStream(_ apply: @escaping @MainActor @Sendable () -> Element) -> AsyncStream<Element> {
        AsyncStream { continuation in
            let loop = ObservationLoop(apply: apply, continuation: continuation)
            Task { @MainActor in
                loop.start()
            }
        }
    }
    
    @MainActor
    private class ObservationLoop {
        let apply: @MainActor @Sendable () -> Element
        let continuation: AsyncStream<Element>.Continuation
        private var isTerminated = false
        
        nonisolated init(apply: @escaping @MainActor @Sendable () -> Element, continuation: AsyncStream<Element>.Continuation) {
            self.apply = apply
            self.continuation = continuation
        }
        
        func start() {
            guard !isTerminated else { return }
            
            let result = withObservationTracking {
                apply()
            } onChange: {
                Task { @MainActor in
                    guard !self.isTerminated else { return }
                    self.start()
                }
            }
            
            let yieldResult = continuation.yield(result)
            if case .terminated = yieldResult {
                isTerminated = true
            }
        }
    }
}
