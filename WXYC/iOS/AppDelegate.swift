//
//  AppDelegate.swift
//  WXYC
//
//  Minimal UIApplicationDelegate whose sole job is returning the background-
//  capable INPlayMediaIntent handler for direct (non-extension) SiriKit
//  dispatch — the media-suggestion tile's system entry point (#828, #829).
//  Wired into WXYCApp via @UIApplicationDelegateAdaptor.
//
//  Deliberately implements nothing else. In particular it must never grow
//  application(_:configurationForConnecting:options:) — that method takes
//  precedence over the UIApplicationSceneManifest declared in
//  iOS/Assets/Info.plist, which is what wires WXYC.CarPlaySceneDelegate. An
//  app delegate that implements it would silently break CarPlay scene
//  creation, and nothing in the automated test suite can catch that failure
//  mode short of asserting the selector is absent (see AppDelegateTests). See
//  docs/configuration.md for the full rationale.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Intents
import UIKit
import WXYCIntents

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        if intent is INPlayMediaIntent {
            return PlayMediaIntentHandler()
        }
        return nil
    }
}
