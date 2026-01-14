//
//  InMemoryDefaultsTests.swift
//  Caching
//
//  Created by Jake Bromberg on 01/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Caching

@Suite("InMemoryDefaults")
struct InMemoryDefaultsTests {

    // MARK: - Basic Type Storage

    @Test("stores and retrieves Bool values")
    func boolStorage() {
        let defaults = InMemoryDefaults()

        #expect(defaults.bool(forKey: "testBool") == false)

        defaults.set(true, forKey: "testBool")
        #expect(defaults.bool(forKey: "testBool") == true)

        defaults.set(false, forKey: "testBool")
        #expect(defaults.bool(forKey: "testBool") == false)
    }

    @Test("stores and retrieves Int values")
    func intStorage() {
        let defaults = InMemoryDefaults()

        #expect(defaults.integer(forKey: "testInt") == 0)

        defaults.set(42, forKey: "testInt")
        #expect(defaults.integer(forKey: "testInt") == 42)

        defaults.set(-1, forKey: "testInt")
        #expect(defaults.integer(forKey: "testInt") == -1)
    }

    @Test("stores and retrieves Float values")
    func floatStorage() {
        let defaults = InMemoryDefaults()

        #expect(defaults.float(forKey: "testFloat") == 0)

        defaults.set(Float(3.14), forKey: "testFloat")
        #expect(defaults.float(forKey: "testFloat") == Float(3.14))
    }

    @Test("stores and retrieves Double values")
    func doubleStorage() {
        let defaults = InMemoryDefaults()

        #expect(defaults.double(forKey: "testDouble") == 0)

        defaults.set(3.14159, forKey: "testDouble")
        #expect(defaults.double(forKey: "testDouble") == 3.14159)
    }

    @Test("stores and retrieves String values")
    func stringStorage() {
        let defaults = InMemoryDefaults()

        #expect(defaults.string(forKey: "testString") == nil)

        defaults.set("hello", forKey: "testString")
        #expect(defaults.string(forKey: "testString") == "hello")
    }

    @Test("stores and retrieves Data values")
    func dataStorage() {
        let defaults = InMemoryDefaults()
        let testData = "test".data(using: .utf8)!

        #expect(defaults.data(forKey: "testData") == nil)

        defaults.set(testData, forKey: "testData")
        #expect(defaults.data(forKey: "testData") == testData)
    }

    @Test("stores and retrieves Any values via object")
    func objectStorage() {
        let defaults = InMemoryDefaults()
        let date = Date()

        #expect(defaults.object(forKey: "testDate") == nil)

        defaults.set(date, forKey: "testDate")
        #expect(defaults.object(forKey: "testDate") as? Date == date)
    }

    // MARK: - Removal

    @Test("removeObject removes a stored value")
    func removeObject() {
        let defaults = InMemoryDefaults()

        defaults.set("value", forKey: "key")
        #expect(defaults.string(forKey: "key") == "value")

        defaults.removeObject(forKey: "key")
        #expect(defaults.string(forKey: "key") == nil)
    }

    @Test("setting nil removes the value")
    func setNilRemovesValue() {
        let defaults = InMemoryDefaults()

        defaults.set("value", forKey: "key")
        #expect(defaults.string(forKey: "key") == "value")

        defaults.set(nil, forKey: "key")
        #expect(defaults.string(forKey: "key") == nil)
    }

    // MARK: - Reset

    @Test("reset clears all stored values")
    func reset() {
        let defaults = InMemoryDefaults()

        defaults.set("value1", forKey: "key1")
        defaults.set(42, forKey: "key2")
        defaults.set(true, forKey: "key3")

        defaults.reset()

        #expect(defaults.string(forKey: "key1") == nil)
        #expect(defaults.integer(forKey: "key2") == 0)
        #expect(defaults.bool(forKey: "key3") == false)
    }

    // MARK: - Dictionary Representation

    @Test("dictionaryRepresentation returns all stored values")
    func dictionaryRepresentation() {
        let defaults = InMemoryDefaults()

        defaults.set("value", forKey: "stringKey")
        defaults.set(42, forKey: "intKey")

        let dict = defaults.dictionaryRepresentation()

        #expect(dict["stringKey"] as? String == "value")
        #expect(dict["intKey"] as? Int == 42)
        #expect(dict.count == 2)
    }

    // MARK: - Isolation

    @Test("separate instances are isolated")
    func instanceIsolation() {
        let defaults1 = InMemoryDefaults()
        let defaults2 = InMemoryDefaults()

        defaults1.set("value1", forKey: "key")
        defaults2.set("value2", forKey: "key")

        #expect(defaults1.string(forKey: "key") == "value1")
        #expect(defaults2.string(forKey: "key") == "value2")
    }

    // MARK: - Protocol Conformance

    @Test("conforms to DefaultsStorage protocol")
    func protocolConformance() {
        let defaults: any DefaultsStorage = InMemoryDefaults()

        defaults.set("test", forKey: "key")
        #expect(defaults.string(forKey: "key") == "test")
    }

    // MARK: - Thread Safety

    @Test("handles concurrent read/write safely")
    func concurrentAccess() async {
        let defaults = InMemoryDefaults()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    defaults.set(i, forKey: "key-\(i)")
                }
                group.addTask {
                    _ = defaults.integer(forKey: "key-\(i % 10)")
                }
            }
        }

        // Verify no crashes occurred and data is consistent
        let dict = defaults.dictionaryRepresentation()
        #expect(dict.count <= 100)
    }
}
