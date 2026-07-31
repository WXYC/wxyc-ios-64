//
//  DeferredSessionTokenProvider.swift
//  Core
//
//  A `SessionTokenProvider` that resolves the underlying provider lazily, on
//  every call, via an injected closure. Fixes a construction-order nil
//  capture in `Singletonia`: `Singletonia.shared`'s stored properties (a
//  stored-property initializer) run before `WXYCApp.init()`'s body calls
//  `MusicShareKit.configure(...)`, so anything that captured
//  `MusicShareKit.authService` directly at that point captured `nil`
//  permanently. Wrapping the read in a closure defers it until the token is
//  actually needed, by which point `configure(...)` has run.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

public struct DeferredSessionTokenProvider: SessionTokenProvider {
    private let resolve: @Sendable () -> SessionTokenProvider?

    /// - Parameter resolve: Evaluated on every call, so a provider wired up
    ///   after this wrapper is constructed is still picked up. Returns nil
    ///   until the underlying provider exists.
    public init(_ resolve: @escaping @Sendable () -> SessionTokenProvider?) {
        self.resolve = resolve
    }

    public func token() async throws -> String {
        try await provider().token()
    }

    public func reauthenticate(previousToken: String) async throws -> String {
        try await provider().reauthenticate(previousToken: previousToken)
    }

    private func provider() throws -> SessionTokenProvider {
        guard let provider = resolve() else {
            throw SessionTokenProviderError.notConfigured
        }
        return provider
    }
}
