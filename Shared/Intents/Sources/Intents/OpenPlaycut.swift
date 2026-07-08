//
//  OpenPlaycut.swift
//  Intents
//
//  Foregrounds the app on a specific playcut. The framework surfaces this intent
//  as the `OpenIntent` for `PlaycutEntity`, so Spotlight results, Siri hand-offs,
//  and shortcut invocations route through a single deep-link path.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct OpenPlaycut: AppIntent, OpenIntent {
    public static let title: LocalizedStringResource = "Open Playcut"
    public static let description = IntentDescription("Opens a WXYC playcut in the app.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Playcut")
    public var target: PlaycutEntity

    public init() { }

    public init(target: PlaycutEntity) {
        self.target = target
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        if let url = PlaycutDeepLink.url(for: target.id.value) {
            #if canImport(UIKit) && !os(watchOS)
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            #endif
        }
        return .result()
    }
}
