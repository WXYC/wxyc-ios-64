//
//  IntentUtilities.swift
//  Intents
//
//  Shared utilities for App Intents.
//

public struct IntentError: Error {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}
