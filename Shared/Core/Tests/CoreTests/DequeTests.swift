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
    
    @Test
    func testPrepend() {
        var deque = Deque<Int>()
        deque.prepend(3)
        deque.prepend(2)
        deque.prepend(1)

        #expect(deque.count == 3)
        #expect(deque[0] == 1)
        #expect(deque[1] == 2)
        #expect(deque[2] == 3)
        #expect(deque.first == 1)
        #expect(deque.last == 3)
    }

    @Test
    func testPrependAndAppend() {
        var deque = Deque<Int>()
        deque.append(2)
        deque.append(3)
        deque.prepend(1)

        #expect(deque.count == 3)
        #expect(Array(deque) == [1, 2, 3])
    }

    @Test
    func testRemoveLast() {
        var deque = Deque<Int>()
        deque.append(1)
        deque.append(2)
        deque.append(3)

        let last = deque.removeLast()
        #expect(last == 3)
        #expect(deque.count == 2)
        #expect(deque[0] == 1)
        #expect(deque[1] == 2)
        #expect(deque.last == 2)
    }

    @Test
    func testRemoveLastFromSingleElement() {
        var deque = Deque<Int>()
        deque.append(42)

        let last = deque.removeLast()
        #expect(last == 42)
        #expect(deque.isEmpty)
    }

    @Test
    func testExpressibleByArrayLiteral() {
        let deque: Deque<Int> = [1, 2, 3, 4, 5]
        #expect(deque.count == 5)
        #expect(Array(deque) == [1, 2, 3, 4, 5])
    }

    @Test
    func testEquatable() {
        let deque1: Deque<Int> = [1, 2, 3]
        let deque2: Deque<Int> = [1, 2, 3]
        let deque3: Deque<Int> = [1, 2, 4]
        let deque4: Deque<Int> = [1, 2]

        #expect(deque1 == deque2)
        #expect(deque1 != deque3)
        #expect(deque1 != deque4)
    }

    @Test
    func testHashable() {
        let deque1: Deque<Int> = [1, 2, 3]
        let deque2: Deque<Int> = [1, 2, 3]
        let deque3: Deque<Int> = [1, 2, 4]

        var hasher1 = Hasher()
        hasher1.combine(deque1)
        let hash1 = hasher1.finalize()

        var hasher2 = Hasher()
        hasher2.combine(deque2)
        let hash2 = hasher2.finalize()

        var hasher3 = Hasher()
        hasher3.combine(deque3)
        let hash3 = hasher3.finalize()

        #expect(hash1 == hash2)
        #expect(hash1 != hash3)
    }

    @Test
    func testCapacityGrowth() {
        var deque = Deque<Int>()
        // Add enough elements to trigger growth
        for i in 0..<20 {
            deque.append(i)
        }

        #expect(deque.count == 20)
        #expect(Array(deque) == Array(0..<20))
    }

    @Test
    func testCapacityShrinking() {
        var deque = Deque<Int>()
        // Fill to trigger growth
        for i in 0..<20 {
            deque.append(i)
        }

        // Remove most elements to trigger shrinking
        deque.removeFirst(15)

        #expect(deque.count == 5)
        #expect(Array(deque) == Array(15..<20))
    }

    @Test
    func testRemoveFirstZero() {
        var deque = Deque<Int>()
        deque.append(1)
        deque.append(2)
        deque.append(3)

        deque.removeFirst(0)
        #expect(deque.count == 3)
        #expect(Array(deque) == [1, 2, 3])
    }

    @Test
    func testRemoveFirstAll() {
        var deque = Deque<Int>()
        for i in 1...5 {
            deque.append(i)
        }

        deque.removeFirst(5)
        #expect(deque.isEmpty)
    }

    @Test
    func testCircularBufferWrapping() {
        var deque = Deque<Int>()
        // Fill to capacity
        for i in 0..<8 {
            deque.append(i)
        }

        // Remove from front to create wrap-around scenario
        deque.removeFirst(4)

        // Add more to test wrapping
        for i in 8..<12 {
            deque.append(i)
        }

        #expect(deque.count == 8)
        #expect(Array(deque) == Array(4..<12))
    }

    @Test
    func testPrependMany() {
        var deque = Deque<Int>()
        deque.append(3)
        deque.append(4)
        deque.append(5)

        deque.prepend(2)
        deque.prepend(1)
        deque.prepend(0)

        #expect(deque.count == 6)
        #expect(Array(deque) == [0, 1, 2, 3, 4, 5])
    }

    @Test
    func testCollectionIndices() {
        let deque: Deque<Int> = [10, 20, 30, 40, 50]

        #expect(deque.startIndex == 0)
        #expect(deque.endIndex == 5)
        #expect(deque.index(after: 0) == 1)
        #expect(deque.index(after: 4) == 5)
    }

    @Test
    func testRandomAccessCollection() {
        let deque: Deque<Int> = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

        // Test distance calculation
        #expect(deque.distance(from: 0, to: 10) == 10)
        #expect(deque.distance(from: 2, to: 7) == 5)

        // Test index offset
        #expect(deque.index(0, offsetBy: 5) == 5)
        #expect(deque.index(5, offsetBy: -3) == 2)
    }
}
