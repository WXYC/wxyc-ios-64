//
//  AppDelegateTests.swift
//  WXYC
//
//  Covers AppDelegate's single responsibility (#829): returning
//  PlayMediaIntentHandler for INPlayMediaIntent so a media-suggestion tile
//  can dispatch in the background. Also guards the constraint that makes this
//  delegate safe to have at all — it must never implement
//  application(_:configurationForConnecting:options:), which would take
//  precedence over the UIApplicationSceneManifest in Info.plist and silently
//  break CarPlay scene creation. See docs/configuration.md.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Intents
import UIKit
import WXYCIntents
@testable import WXYC

@Suite("AppDelegate")
@MainActor
struct AppDelegateTests {
    @Test("Returns a PlayMediaIntentHandler for INPlayMediaIntent")
    func handlerForPlayMediaIntent() {
        let delegate = AppDelegate()

        let handler = delegate.application(UIApplication.shared, handlerFor: makeIntent())

        #expect(handler is PlayMediaIntentHandler)
    }

    @Test("Returns nil for an intent it doesn't recognize")
    func handlerForUnrecognizedIntent() {
        let delegate = AppDelegate()

        let handler = delegate.application(UIApplication.shared, handlerFor: INIntent())

        #expect(handler == nil)
    }

    @Test("Never implements application(_:configurationForConnecting:options:) — it would silently break CarPlay scene creation")
    func doesNotImplementSceneConfigurationHandler() {
        let delegate = AppDelegate()
        let selector = #selector(UIApplicationDelegate.application(_:configurationForConnecting:options:))

        #expect(!delegate.responds(to: selector))
    }
}

private func makeIntent() -> INPlayMediaIntent {
    INPlayMediaIntent(
        mediaItems: nil,
        mediaContainer: nil,
        playShuffled: nil,
        resumePlayback: nil,
        playbackQueueLocation: .unknown,
        playbackSpeed: nil
    )
}
