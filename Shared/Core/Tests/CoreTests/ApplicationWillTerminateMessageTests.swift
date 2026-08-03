//
//  ApplicationWillTerminateMessageTests.swift
//  Core
//
//  Tests for ApplicationWillTerminateMessage's platform bridging. The message
//  bridges UIApplication.willTerminateNotification on UIKit platforms and
//  NSApplication.willTerminateNotification on AppKit (macOS), so it exists on
//  every platform with an app-termination notification (all but watchOS).
//
//  Created by Jake Bromberg on 08/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Core

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if !os(watchOS)

@Suite("ApplicationWillTerminateMessage")
struct ApplicationWillTerminateMessageTests {

    @Test("name bridges to the platform's app-termination notification")
    func nameMatchesPlatformNotification() {
        #if canImport(UIKit)
        #expect(ApplicationWillTerminateMessage.name == UIApplication.willTerminateNotification)
        #elseif canImport(AppKit)
        #expect(ApplicationWillTerminateMessage.name == NSApplication.willTerminateNotification)
        #endif
    }

    @Test("makeMessage returns a message for a matching notification")
    func makeMessageForMatchingNotification() {
        let notification = Notification(name: ApplicationWillTerminateMessage.name, object: nil)
        #expect(ApplicationWillTerminateMessage.makeMessage(notification) != nil)
    }

    @Test("makeMessage returns nil for a non-matching notification")
    func makeMessageForNonMatchingNotification() {
        let notification = Notification(name: .init("com.wxyc.core.not-the-termination-notification"), object: nil)
        #expect(ApplicationWillTerminateMessage.makeMessage(notification) == nil)
    }
}

#endif
