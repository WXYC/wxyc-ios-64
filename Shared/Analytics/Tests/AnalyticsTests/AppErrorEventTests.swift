//
//  AppErrorEventTests.swift
//  Analytics
//
//  Tests for the AppErrorEvent type used by CompositeErrorReporter to report
//  errors to PostHog with description, context, category, and a merged extra payload.
//
//  Created by Jake Bromberg on 06/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Analytics

@Suite("AppErrorEvent")
struct AppErrorEventTests {

    // MARK: - Event Name

    @Test("Event name is 'error'")
    func eventName() {
        #expect(AppErrorEvent.name == "error")
    }

    // MARK: - Property Serialization

    @Test("Properties include description, context, and category")
    func baseProperties() throws {
        let event = AppErrorEvent(
            description: "The operation couldn't be completed.",
            context: "DiskCache.read",
            category: "cache"
        )
        let props = try #require(event.properties)

        #expect(props["description"] as? String == "The operation couldn't be completed.")
        #expect(props["context"] as? String == "DiskCache.read")
        #expect(props["category"] as? String == "cache")
    }

    @Test("Empty extra leaves the three base properties alone")
    func emptyExtraDefaults() throws {
        let event = AppErrorEvent(
            description: "boom",
            context: "ctx",
            category: "cat"
        )
        let props = try #require(event.properties)

        #expect(props.count == 3)
        #expect(props["description"] as? String == "boom")
        #expect(props["context"] as? String == "ctx")
        #expect(props["category"] as? String == "cat")
    }

    @Test("Non-empty extra is merged into properties")
    func extraIsMerged() throws {
        let event = AppErrorEvent(
            description: "HTTP failure",
            context: "Intents.handle",
            category: "intents",
            extra: ["status": "404", "url": "https://example.test"]
        )
        let props = try #require(event.properties)

        #expect(props["description"] as? String == "HTTP failure")
        #expect(props["context"] as? String == "Intents.handle")
        #expect(props["category"] as? String == "intents")
        #expect(props["status"] as? String == "404")
        #expect(props["url"] as? String == "https://example.test")
    }

    @Test("Extra overrides base keys on collision")
    func extraOverridesBaseOnCollision() throws {
        let event = AppErrorEvent(
            description: "base desc",
            context: "base ctx",
            category: "base cat",
            extra: ["category": "override"]
        )
        let props = try #require(event.properties)

        #expect(props["category"] as? String == "override")
        // Non-colliding base keys still present.
        #expect(props["description"] as? String == "base desc")
        #expect(props["context"] as? String == "base ctx")
    }
}
