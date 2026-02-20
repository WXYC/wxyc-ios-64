//
//  WidgetRelevanceUpdating.swift
//  AppServices
//
//  Protocol abstracting RelevantIntentManager for testability.
//  The production implementation delegates to the system manager;
//  tests inject a mock to verify relevance hint behavior.
//
//  Created by Claude on 02/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if canImport(WidgetKit)
import AppIntents
import WidgetKit

/// Abstracts `RelevantIntentManager` so widget relevance can be tested
/// without hitting the system API.
@MainActor
public protocol WidgetRelevanceUpdating: Sendable {
    func updateRelevantIntents(_ intents: sending [RelevantIntent]) async
}

/// Production implementation that delegates to `RelevantIntentManager.shared`.
@MainActor
public struct SystemWidgetRelevanceUpdater: WidgetRelevanceUpdating {
    public init() {}

    public func updateRelevantIntents(_ intents: sending [RelevantIntent]) async {
        #if os(iOS)
        do {
            try await RelevantIntentManager.shared.updateRelevantIntents(intents)
        } catch {
            // Relevance hints are best-effort; silently ignore errors.
        }
        #endif
    }
}
#endif
