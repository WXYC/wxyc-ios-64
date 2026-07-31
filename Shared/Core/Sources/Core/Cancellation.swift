//
//  Cancellation.swift
//  Core
//
//  Predicate for recognizing cooperative cancellation across the async network
//  stack, where it surfaces in two forms that do not bridge to each other.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Returns `true` when `error` represents cooperative cancellation rather than a
/// genuine failure worth reporting.
///
/// Two distinct forms surface across the async network stack and do **not**
/// bridge to each other:
/// - `CancellationError` — thrown by Swift concurrency primitives such as
///   `Task.sleep(...)` and `Task.checkCancellation()`.
/// - `URLError(.cancelled)` — thrown by `URLSession.data(for:)` when its request
///   is cancelled (e.g. a data source torn down mid-flight).
///
/// Because `URLError(.cancelled)` can surface without the surrounding task's
/// `isCancelled` flag being set, cancellation must be classified from the error
/// itself. Callers that also want to treat a cancelled *task* as cancellation
/// should OR this with `Task.isCancelled` at the call site.
public func isCancellation(_ error: any Error) -> Bool {
    if error is CancellationError {
        return true
    }
    if let urlError = error as? URLError, urlError.code == .cancelled {
        return true
    }
    return false
}
