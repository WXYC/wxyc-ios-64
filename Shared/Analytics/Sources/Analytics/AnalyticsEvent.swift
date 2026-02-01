//
//  AnalyticsEvent.swift
//  Analytics
//
//  Defines the AnalyticsEvent protocol for type-safe, structured analytics tracking.
//  Event names are derived automatically from type names using snake_case conversion.
//
//  Created by Antigravity on 01/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A structured analytics event that can be tracked.
///
/// Event names are derived automatically from the type name using snake_case conversion:
/// - `QualitySessionSummary` → `quality_session_summary`
/// - `ThemePickerEnteredEvent` → `theme_picker_entered_event`
/// - `CPUUsageEvent` → `cpu_usage_event`
///
/// To override the automatic name, implement a custom static `name` property.
public protocol AnalyticsEvent: Sendable {
    /// The name of the event to track.
    ///
    /// Default implementation derives the name from the type name using snake_case conversion.
    static var name: String { get }

    /// The properties associated with the event.
    var properties: [String: Any]? { get }
}

extension AnalyticsEvent {
    /// Default implementation derives the event name from the type name.
    public static var name: String {
        String(describing: Self.self).convertedToSnakeCase()
    }
}

extension String {
    /// Converts a PascalCase type name to snake_case.
    ///
    /// Handles acronyms by keeping consecutive uppercase letters together:
    /// - `CPUUsage` → `cpu_usage`
    /// - `URLSession` → `url_session`
    /// - `QualitySessionSummary` → `quality_session_summary`
    func convertedToSnakeCase() -> String {
        guard !isEmpty else { return self }

        var result = ""
        var pendingUppercase = ""

        for (index, character) in enumerated() {
            if character.isUppercase {
                if !pendingUppercase.isEmpty {
                    // Continue accumulating uppercase (part of acronym)
                    pendingUppercase.append(character)
                } else {
                    // Start of new uppercase sequence
                    if index > 0 {
                        result += "_"
                    }
                    pendingUppercase = String(character)
                }
            } else {
                if pendingUppercase.count > 1 {
                    // End of acronym - all but last char are the acronym
                    let acronym = String(pendingUppercase.dropLast())
                    let transitionChar = pendingUppercase.last!
                    result += acronym.lowercased()
                    result += "_"
                    result += transitionChar.lowercased()
                } else if !pendingUppercase.isEmpty {
                    // Single uppercase letter
                    result += pendingUppercase.lowercased()
                }
                pendingUppercase = ""
                result += String(character)
            }
        }

        // Handle any remaining uppercase characters (e.g., trailing acronym)
        if !pendingUppercase.isEmpty {
            result += pendingUppercase.lowercased()
        }

        return result
    }
}
