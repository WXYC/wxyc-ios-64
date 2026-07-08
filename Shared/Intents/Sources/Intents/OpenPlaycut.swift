//
//  OpenPlaycut.swift
//  Intents
//
//  Foregrounds the app on a specific playcut. Because the intent runs in-app
//  once `openAppWhenRun` foregrounds it, `perform()` posts the typed
//  `PlaycutOpenMessage` directly rather than round-tripping through the
//  `wxyc://` URL scheme — the observer that maps the id to a detail view is
//  the same either way.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation

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
        NotificationCenter.default.post(
            PlaycutOpenMessage(playcutID: target.id),
            subject: nil
        )
        return .result()
    }
}
