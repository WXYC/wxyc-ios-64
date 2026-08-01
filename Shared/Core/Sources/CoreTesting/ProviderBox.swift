//
//  ProviderBox.swift
//  CoreTesting
//
//  Thread-safe nil-then-set `SessionTokenProvider` holder. Replaces the
//  verbatim clones in CoreTests' `DeferredSessionTokenProviderTests` and
//  ConcertsTests' `OnTourConcertsE2ETests`.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import os

/// A mutable holder a test flips between constructing a
/// `DeferredSessionTokenProvider` and calling it, standing in for
/// `MusicShareKit.authService` transitioning from `nil` (pre-`configure`) to
/// a real provider (post-`configure`). Backed by `OSAllocatedUnfairLock`
/// rather than an actor because `DeferredSessionTokenProvider`'s resolver
/// closure is synchronous.
public final class ProviderBox: Sendable {
    private let lock = OSAllocatedUnfairLock<SessionTokenProvider?>(initialState: nil)

    public init() {}

    public var provider: SessionTokenProvider? {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}
