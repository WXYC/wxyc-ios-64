//
//  CanOpenURLAction.swift
//  WXYC
//
//  The environment's answer to "can this app open that URL?", the read-side
//  peer of SwiftUI's `openURL`. SwiftUI has no `canOpenURL`, so the default
//  wraps `UIApplication.canOpenURL`, which is the one reason this touches
//  UIKit. Keeping it in the environment lets previews and tests inject an
//  answer and keeps the Mac Catalyst rule out of the views that ask.
//
//  Created by Jake Bromberg on 10/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import UIKit

struct CanOpenURLAction: Sendable {
    private let handler: @MainActor @Sendable (URL) -> Bool

    init(_ handler: @escaping @MainActor @Sendable (URL) -> Bool) {
        self.handler = handler
    }

    @MainActor
    func callAsFunction(_ url: URL) -> Bool {
        handler(url)
    }

    /// `UIApplication.canOpenURL`, which answers only for schemes listed under
    /// `LSApplicationQueriesSchemes` in Info.plist. Always `false` on Mac
    /// Catalyst, where the only app this is asked about (the iPhone-only DJ
    /// app) can't be installed.
    static let system = CanOpenURLAction { url in
        #if targetEnvironment(macCatalyst)
        false
        #else
        UIApplication.shared.canOpenURL(url)
        #endif
    }
}

extension EnvironmentValues {
    @Entry var canOpenURL = CanOpenURLAction.system
}
