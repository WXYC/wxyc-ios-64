//
//  AnalyticsEventMacro.swift
//  Analytics
//
//  Macro declaration for @AnalyticsEvent that synthesizes protocol conformance
//  and the properties computed property.
//
//  Created by Claude on 01/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

/// A macro that automatically synthesizes `AnalyticsEvent` protocol conformance.
///
/// When applied to a struct, this macro:
/// 1. Adds `AnalyticsEvent` protocol conformance
/// 2. Synthesizes a `name` static property from the type name (converted to snake_case),
///    unless an explicit `name` is already defined
/// 3. Synthesizes a `properties` computed property that returns a dictionary of all
///    stored properties with their names converted to snake_case
///
/// ## Example
///
/// ```swift
/// @AnalyticsEvent
/// public struct AppLaunch {
///     public let hasUsedThemePicker: Bool
///     public let buildType: String
/// }
/// ```
///
/// Expands to:
///
/// ```swift
/// public struct AppLaunch {
///     public let hasUsedThemePicker: Bool
///     public let buildType: String
///
///     public static let name: String = "app_launch"
///
///     public var properties: [String: Any]? {
///         [
///             "has_used_theme_picker": hasUsedThemePicker,
///             "build_type": buildType
///         ]
///     }
/// }
///
/// extension AppLaunch: AnalyticsEvent {}
/// ```
///
/// ## Overriding the Event Name
///
/// For backwards compatibility with existing event names, you can provide an explicit
/// `name` property and it will not be overwritten:
///
/// ```swift
/// @AnalyticsEvent
/// public struct AppLaunch {
///     public static let name = "app launch"  // Uses space instead of underscore
///     public let hasUsedThemePicker: Bool
/// }
/// ```
///
/// ## Events Without Properties
///
/// For events with no properties, the macro generates `nil`:
///
/// ```swift
/// @AnalyticsEvent
/// public struct PartyHornPresented {}
/// // Generates: public var properties: [String: Any]? { nil }
/// ```
@attached(member, names: named(name), named(properties))
@attached(extension, conformances: AnalyticsEvent)
public macro AnalyticsEvent() = #externalMacro(module: "AnalyticsMacros", type: "AnalyticsEventMacro")
