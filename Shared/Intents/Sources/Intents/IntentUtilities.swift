//
//  IntentUtilities.swift
//  Intents
//
//  Shared utilities for App Intents.
//
//  Created by Jake Bromberg on 01/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

public struct IntentError: Error {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}
