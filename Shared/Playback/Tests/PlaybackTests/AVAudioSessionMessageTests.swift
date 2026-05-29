//
//  AVAudioSessionMessageTests.swift
//  Playback
//
//  Round-trip and post-and-observe tests for InterruptionMessage and
//  RouteChangeMessage — the typed wrappers around AVAudioSession's
//  interruptionNotification and routeChangeNotification.
//
//  Created by Jake Bromberg on 05/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS) || os(tvOS)
import Testing
import Foundation
import AVFoundation
import Core
@testable import PlaybackCore

@Suite("AVAudioSession messages", .serialized)
@MainActor
struct AVAudioSessionMessageTests {

    // MARK: - InterruptionMessage

    @Test("InterruptionMessage round-trips through makeNotification / makeMessage")
    func interruptionMessageRoundTrip() {
        let original = InterruptionMessage(type: .began, options: [])
        let notification = InterruptionMessage.makeNotification(original, object: nil)
        let recovered = InterruptionMessage.makeMessage(notification)

        #expect(notification.name == AVAudioSession.interruptionNotification)
        #expect(recovered?.type == .began)
        #expect(recovered?.options == [])
    }

    @Test("InterruptionMessage round-trips with .ended + .shouldResume")
    func interruptionMessageRoundTripEnded() {
        let original = InterruptionMessage(type: .ended, options: .shouldResume)
        let notification = InterruptionMessage.makeNotification(original, object: nil)
        let recovered = InterruptionMessage.makeMessage(notification)

        #expect(recovered?.type == .ended)
        #expect(recovered?.options.contains(.shouldResume) == true)
    }

    @Test("InterruptionMessage.makeMessage returns nil when payload is missing")
    func interruptionMessageNilForMissingPayload() {
        let empty = Notification(name: AVAudioSession.interruptionNotification, object: nil, userInfo: nil)
        #expect(InterruptionMessage.makeMessage(empty) == nil)

        let wrongKeys = Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: ["something": 1]
        )
        #expect(InterruptionMessage.makeMessage(wrongKeys) == nil)
    }

    @Test("InterruptionMessage delivers through addMainActorObserver")
    func interruptionMessagePostAndObserve() async {
        let center = NotificationCenter()
        let expected = InterruptionMessage(type: .began, options: [])
        let received = AsyncStream<InterruptionMessage>.makeStream()

        let token = center.addMainActorObserver(
            for: InterruptionMessage.self
        ) { message in
            received.continuation.yield(message)
            received.continuation.finish()
        }

        center.post(expected, subject: nil as AVAudioSession?)

        var got: InterruptionMessage?
        for await message in received.stream {
            got = message
            break
        }

        #expect(got?.type == .began)
        #expect(got?.options == [])
        center.removeObserver(token)
    }

    // MARK: - RouteChangeMessage

    @Test("RouteChangeMessage round-trips through makeNotification / makeMessage")
    func routeChangeMessageRoundTrip() {
        let original = RouteChangeMessage(reason: .oldDeviceUnavailable)
        let notification = RouteChangeMessage.makeNotification(original, object: nil)
        let recovered = RouteChangeMessage.makeMessage(notification)

        #expect(notification.name == AVAudioSession.routeChangeNotification)
        #expect(recovered?.reason == .oldDeviceUnavailable)
    }

    @Test("RouteChangeMessage.makeMessage returns nil when payload is missing")
    func routeChangeMessageNilForMissingPayload() {
        let empty = Notification(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: nil)
        #expect(RouteChangeMessage.makeMessage(empty) == nil)

        let wrongKeys = Notification(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: ["something": 1]
        )
        #expect(RouteChangeMessage.makeMessage(wrongKeys) == nil)
    }

    @Test("RouteChangeMessage delivers through addMainActorObserver")
    func routeChangeMessagePostAndObserve() async {
        let center = NotificationCenter()
        let expected = RouteChangeMessage(reason: .newDeviceAvailable)
        let received = AsyncStream<RouteChangeMessage>.makeStream()

        let token = center.addMainActorObserver(
            for: RouteChangeMessage.self
        ) { message in
            received.continuation.yield(message)
            received.continuation.finish()
        }

        center.post(expected, subject: nil as AVAudioSession?)

        var got: RouteChangeMessage?
        for await message in received.stream {
            got = message
            break
        }

        #expect(got?.reason == .newDeviceAvailable)
        center.removeObserver(token)
    }
}
#endif
