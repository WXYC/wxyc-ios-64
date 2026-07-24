//
//  OpenConcert.swift
//  Intents
//
//  Foregrounds the app on a specific concert. Because the intent runs in-app
//  once `openAppWhenRun` foregrounds it, `perform()` posts the typed
//  `ConcertOpenMessage` directly rather than round-tripping through the
//  `wxyc://` URL scheme — the existing Singletonia -> PendingConcertLink ->
//  OnTourTabView.resolveConcert ladder that opens the poster detail is the
//  same either way (#537), mirroring `OpenPlaycut`.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation

public struct OpenConcert: AppIntent, OpenIntent {
    public static let title: LocalizedStringResource = "Open Concert"
    public static let description = IntentDescription("Opens a WXYC On Tour concert in the app.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Concert")
    public var target: ConcertEntity

    public init() { }

    public init(target: ConcertEntity) {
        self.target = target
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        // `target.id` bridges back to the backend's `Int` id space that
        // `ConcertOpenMessage` speaks (see `EntityID.concertID`). Every
        // `ConcertEntity` this app constructs already satisfies the bridge,
        // so this guard only covers a value that can't arise in practice
        // rather than crashing on a force-unwrap.
        if let concertID = target.id.concertID {
            NotificationCenter.default.post(
                ConcertOpenMessage(concertID: concertID, source: .scheme),
                subject: nil
            )
        }
        return .result()
    }
}
