//
//  StructuredPostHogAnalytics.swift
//  Analytics
//
//  PostHog implementation of AnalyticsService using structured AnalyticsEvent types.
//
//  Created by Antigravity on 01/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import PostHog

/// Production seam wrapping PostHog's capture API so the build_type stamping path
/// is unit-testable. The only production implementation forwards to PostHogSDK.shared.
///
/// `Sendable` because `StructuredPostHogAnalytics` is now a plain `struct: Sendable`
/// (no `@unchecked`) — the compiler needs every stored property, including this
/// existential, to be provably Sendable. Conformers must be genuinely thread-safe
/// (e.g. `PostHogSDKClient` below has no stored state; test doubles guard any
/// mutable state with a lock).
protocol PostHogClientProtocol: Sendable {
    func capture(_ name: String, properties: [String: Any]?)
    func captureException(_ error: any Error, properties: [String: Any]?)
}

private struct PostHogSDKClient: PostHogClientProtocol {
    func capture(_ name: String, properties: [String: Any]?) {
        PostHogSDK.shared.capture(name, properties: properties)
    }

    func captureException(_ error: any Error, properties: [String: Any]?) {
        PostHogSDK.shared.captureException(error, properties: properties)
    }
}

/// A concrete implementation of AnalyticsService that reports to PostHog.
///
/// Stamps `build_type` (sourced from the `WXYC_BUILD_TYPE` Info.plist key) onto every
/// captured event's properties. Typed event properties win on collision — if an event's
/// `properties` dict already contains `"build_type"`, that value is preserved.
public struct StructuredPostHogAnalytics: AnalyticsService, Sendable {
    public static let shared = StructuredPostHogAnalytics()

    private let client: PostHogClientProtocol
    private let buildType: String
    private let exceptionGate: ExceptionGate

    private init() {
        let buildType = (Bundle.main.infoDictionary?["WXYC_BUILD_TYPE"] as? String) ?? "unknown"
        self.init(client: PostHogSDKClient(), buildType: buildType)
    }

    internal init(client: PostHogClientProtocol, buildType: String, exceptionGate: ExceptionGate = ExceptionGate()) {
        self.client = client
        self.buildType = buildType
        self.exceptionGate = exceptionGate
    }

    public func capture<T: AnalyticsEvent>(_ event: T) {
        var properties = event.properties ?? [:]
        if properties["build_type"] == nil {
            properties["build_type"] = buildType
        }
        client.capture(T.name, properties: properties)
    }

    /// Sends a handled error as `$exception` if it passes the ``ExceptionGate``. `capture(_:)`
    /// is not gated, so MetricKit crash and hang diagnostics always go out.
    public func captureException(_ error: any Error, properties: [String: Any]?) {
        guard exceptionGate.admit(key: Self.dedupeKey(for: error, properties: properties)) else {
            return
        }
        var properties = properties ?? [:]
        if properties["build_type"] == nil {
            properties["build_type"] = buildType
        }
        client.captureException(error, properties: properties)
    }

    /// The error's type plus its fingerprint when it has one, otherwise its message (domain and
    /// code for an `NSError`) and the `context` property.
    private static func dedupeKey(for error: any Error, properties: [String: Any]?) -> String {
        let type = String(reflecting: Swift.type(of: error))
        if let fingerprint = properties?["$exception_fingerprint"] as? String {
            return "\(type)|\(fingerprint)"
        }
        let message: String
        if Swift.type(of: error) == NSError.self {
            let nsError = error as NSError
            message = "\(nsError.domain)#\(nsError.code)"
        } else {
            message = "\(error)"
        }
        let context = properties?["context"] as? String ?? ""
        return "\(type)|\(message)|\(context)"
    }
}
