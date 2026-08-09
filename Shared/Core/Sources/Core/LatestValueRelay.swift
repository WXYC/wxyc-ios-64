//
//  LatestValueRelay.swift
//  Core
//
//  Carries the latest of some state from a synchronous caller to an async
//  handler, in order. Lives in Core, alongside the other dependency-free
//  concurrency utilities, so any package can reach it.
//
//  Created by Jake Bromberg on 08/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

/// Delivers state pushed from a synchronous context to an async handler, one
/// value at a time and in the order it was sent.
///
/// A bare `Task { await destination.apply(x) }` per push is the obvious way to
/// bridge a synchronous callback into an actor, and it is wrong whenever the
/// order of the pushes carries meaning. Unstructured tasks have no relative
/// ordering guarantee: two created back to back may reach the destination in
/// either order, so the *last* push does not reliably produce the *final* state.
///
/// That is not theoretical here. Successive scene-phase edges push foreground
/// state at `PlaylistService`, and a rapid `.background`/`.active` pair
/// delivered through per-push tasks arrived inverted, latching
/// `isForegrounded = false` while the app was on screen. Nothing re-checks
/// that flag once set, so the `live-fs-topic` SSE subscription stayed down for
/// the remainder of the session and the playlist fell back to its 300 s
/// reconciliation poll — the app visibly trailing the flowsheet.
///
/// ``send(_:)`` hands the value to a one-slot `AsyncStream` buffer
/// synchronously, so order is fixed at the call site, in the caller's isolation
/// domain, before any suspension can reorder anything. A single long-lived task
/// drains that buffer.
///
/// ## Superseded values are dropped
///
/// The buffer holds one value. A push that arrives while the handler is still
/// working on an earlier one replaces whatever was waiting, so the handler sees
/// the first value and then the newest — never the stale middle of a burst.
///
/// That makes this a relay for *state*, where the latest push describes the
/// world and the ones it overtook no longer do. It is the wrong type for events
/// that accumulate, where dropping one loses information; those want a chain
/// that runs every item, like the one `PlaycutHistoryStore.ingest(_:)` open-codes.
///
/// ## Lifetime
///
/// The handler starts draining at construction — there is no start step to
/// forget, because a relay whose consumer never started would silently swallow
/// everything sent to it. Releasing the relay finishes the stream, which ends
/// the drain task once the handler returns.
///
/// ```swift
/// let foreground = LatestValueRelay<Bool> { [service] isForegrounded in
///     await service.setForegrounded(isForegrounded)
/// }
/// foreground.send(true)
/// ```
public final class LatestValueRelay<Value: Sendable>: Sendable {
    private let continuation: AsyncStream<Value>.Continuation

    /// Creates a relay and starts delivering to `handle`.
    ///
    /// - Parameter handle: Runs once per delivered value, never concurrently
    ///   with itself. Capture only what it needs: it outlives the call to
    ///   `init` and holds its captures for the relay's lifetime.
    public init(_ handle: @escaping @Sendable (Value) async -> Void) {
        let (stream, continuation) = AsyncStream<Value>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.continuation = continuation

        Task {
            for await value in stream {
                await handle(value)
            }
        }
    }

    /// Hands `value` to the handler, superseding any value still waiting.
    ///
    /// Returns immediately — this is the bridge out of a synchronous caller.
    public func send(_ value: Value) {
        continuation.yield(value)
    }

    deinit {
        // Ends the drain task. Without this the task would wait on a stream
        // nobody can ever write to again.
        continuation.finish()
    }
}
