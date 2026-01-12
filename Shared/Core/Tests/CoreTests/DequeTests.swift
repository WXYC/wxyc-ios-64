//
//  DequeTests.swift
//  CoreTests
//

import Testing
@testable import Core

struct DequeTests {
    @Test
    func testEmptyDeque() {
        let deque = Deque<Int>()
        #expect(deque.isEmpty)
        #expect(deque.count == 0)
        #expect(deque.first == nil)
    }
    
    @Test
    func testAppend() {
        var deque = Deque<Int>()
        deque.append(1)
        deque.append(2)
        deque.append(3)
        
        #expect(deque.count == 3)
        #expect(deque[0] == 1)
        #expect(deque[1] == 2)
        #expect(deque[2] == 3)
        #expect(deque.first == 1)
        #expect(deque.last == 3)
    }
    
    @Test
    func testRemoveFirst() {
        var deque = Deque<Int>()
        deque.append(1)
        deque.append(2)
        deque.append(3)
        
        let first = deque.removeFirst()
        #expect(first == 1)
        #expect(deque.count == 2)
        #expect(deque[0] == 2)
        #expect(deque[1] == 3)
    }
    
    @Test
    func testRemoveFirstMultiple() {
        var deque = Deque<Int>()
        for i in 1...5 {
            deque.append(i)
        }
        
        deque.removeFirst(3)
        #expect(deque.count == 2)
        #expect(deque[0] == 4)
        #expect(deque[1] == 5)
    }
    
    @Test
    func testRemoveAll() {
        var deque = Deque<Int>()
        for i in 1...5 {
            deque.append(i)
        }
        
        deque.removeAll()
        #expect(deque.isEmpty)
        #expect(deque.count == 0)
    }
    
    @Test
    func testArrayConversion() {
        var deque = Deque<Int>()
        for i in 1...5 {
            deque.append(i)
        }
        
        let array = Array(deque)
        #expect(array == [1, 2, 3, 4, 5])
    }
    
    @Test
    func testCopyOnWrite() {
        var deque1 = Deque<Int>()
        deque1.append(1)
        deque1.append(2)
        
        var deque2 = deque1
        deque2.append(3)
        
        // deque1 should be unchanged
        #expect(deque1.count == 2)
        #expect(deque2.count == 3)
    }
    
    @Test
    func testCircularBuffer() {
        var deque = Deque<Int>()
        // Fill and partially empty to test circular buffer
        for i in 1...10 {
            deque.append(i)
        }
        
        // Remove from front
        deque.removeFirst(5)
        
        // Add more
        for i in 11...15 {
            deque.append(i)
        }
        
        #expect(deque.count == 10)
        let array = Array(deque)
        #expect(array == [6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
    }
    
    @Test
    func testSubscript() {
        var deque = Deque<String>()
        deque.append("a")
        deque.append("b")
        deque.append("c")
        
        #expect(deque[0] == "a")
        #expect(deque[1] == "b")
        #expect(deque[2] == "c")
        
        deque[1] = "x"
        #expect(deque[1] == "x")
    }
}
