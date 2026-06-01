//
//  SafePopFirstTests.swift
//  CoreTests
//
//  Created by Jake Bromberg on 06/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Core

@Suite("safePopFirst Tests")
struct SafePopFirstTests {

    @Test("Returns nil for empty array")
    func returnsNilForEmptyArray() {
        var array: [Int] = []
        #expect(array.safePopFirst() == nil)
        #expect(array.isEmpty)
    }

    @Test("Single-element array returns the element and empty remainder")
    func singleElementReturnsElementAndEmpty() {
        var array = [42]
        let popped = array.safePopFirst()
        #expect(popped?.0 == 42)
        #expect(popped?.1.isEmpty == true)
        #expect(array.isEmpty)
    }

    @Test("Multi-element array returns first element and remainder")
    func multiElementReturnsFirstAndRemainder() {
        var array = [1, 2, 3, 4]
        let popped = array.safePopFirst()
        #expect(popped?.0 == 1)
        #expect(Array(popped?.1 ?? []) == [2, 3, 4])
        #expect(array == [2, 3, 4])
    }

    @Test("Works on String (RangeReplaceableCollection of Character)")
    func worksOnString() {
        var s = "hello"
        let popped = s.safePopFirst()
        #expect(popped?.0 == "h")
        #expect(popped?.1 == "ello")
        #expect(s == "ello")
    }
}
