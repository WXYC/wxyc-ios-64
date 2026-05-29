//
//  UIApplicationMessageTests.swift
//  Playback
//
//  makeMessage/makeNotification symmetry and post-and-observe tests for
//  AppDidEnterBackgroundMessage and AppWillEnterForegroundMessage — the
//  typed wrappers around UIApplication's didEnterBackground and
//  willEnterForeground notifications.
//
//  Created by Jake Bromberg on 05/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS)
import Testing
import Foundation
import UIKit
import Core
@testable import PlaybackCore

@Suite("UIApplication messages", .serialized)
@MainActor
struct UIApplicationMessageTests {

    // MARK: - AppDidEnterBackgroundMessage

    @Test("AppDidEnterBackgroundMessage makeNotification / makeMessage symmetry")
    func didEnterBackgroundSymmetry() {
        let original = AppDidEnterBackgroundMessage()
        let notification = AppDidEnterBackgroundMessage.makeNotification(original, object: nil)
        let recovered = AppDidEnterBackgroundMessage.makeMessage(notification)

        #expect(notification.name == UIApplication.didEnterBackgroundNotification)
        #expect(recovered != nil)
    }

    @Test("AppDidEnterBackgroundMessage delivers through addMainActorObserver")
    func didEnterBackgroundPostAndObserve() async {
        let center = NotificationCenter()
        let received = AsyncStream<Void>.makeStream()

        let token = center.addMainActorObserver(
            for: AppDidEnterBackgroundMessage.self
        ) { _ in
            received.continuation.yield()
            received.continuation.finish()
        }

        center.post(AppDidEnterBackgroundMessage(), subject: nil as UIApplication?)

        var didReceive = false
        for await _ in received.stream {
            didReceive = true
            break
        }

        #expect(didReceive)
        center.removeObserver(token)
    }

    // MARK: - AppWillEnterForegroundMessage

    @Test("AppWillEnterForegroundMessage makeNotification / makeMessage symmetry")
    func willEnterForegroundSymmetry() {
        let original = AppWillEnterForegroundMessage()
        let notification = AppWillEnterForegroundMessage.makeNotification(original, object: nil)
        let recovered = AppWillEnterForegroundMessage.makeMessage(notification)

        #expect(notification.name == UIApplication.willEnterForegroundNotification)
        #expect(recovered != nil)
    }

    @Test("AppWillEnterForegroundMessage delivers through addMainActorObserver")
    func willEnterForegroundPostAndObserve() async {
        let center = NotificationCenter()
        let received = AsyncStream<Void>.makeStream()

        let token = center.addMainActorObserver(
            for: AppWillEnterForegroundMessage.self
        ) { _ in
            received.continuation.yield()
            received.continuation.finish()
        }

        center.post(AppWillEnterForegroundMessage(), subject: nil as UIApplication?)

        var didReceive = false
        for await _ in received.stream {
            didReceive = true
            break
        }

        #expect(didReceive)
        center.removeObserver(token)
    }
}
#endif
