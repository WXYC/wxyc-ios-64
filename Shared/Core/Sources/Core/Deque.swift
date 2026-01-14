//
//  Deque.swift
//  Core
//
//  A minimal double-ended queue implementation extracted from swift-collections
//  to avoid the compilation overhead of the full package.
//
//  / A double-ended queue (deque) that provides efficient insertion and removal
//  / at both ends. Uses a circular buffer for O(1) amortized operations.
//
//  Created by Jake Bromberg on 01/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

public struct Deque<Element>: Sendable where Element: Sendable {
    @usableFromInline
    internal var _storage: _DequeStorage<Element>
    
    /// Creates an empty deque.
    @inlinable
    public init() {
        _storage = _DequeStorage()
    }
    
    /// The number of elements in the deque.
    @inlinable
    public var count: Int {
        _storage.count
    }
    
    /// A Boolean value indicating whether the deque is empty.
    @inlinable
    public var isEmpty: Bool {
        count == 0
    }
    
    /// The first element of the deque, or `nil` if the deque is empty.
    @inlinable
    public var first: Element? {
        guard !isEmpty else { return nil }
        return self[0]
    }
    
    /// The last element of the deque, or `nil` if the deque is empty.
    @inlinable
    public var last: Element? {
        guard !isEmpty else { return nil }
        return self[count - 1]
    }
    
    /// Accesses the element at the specified position.
    @inlinable
    public subscript(position: Int) -> Element {
        get {
            _storage[position]
        }
        set {
            _storage[position] = newValue
        }
    }
    
    /// Appends a new element to the end of the deque.
    @inlinable
    public mutating func append(_ element: Element) {
        _ensureUnique()
        _storage.append(element)
    }
    
    /// Prepends a new element to the beginning of the deque.
    @inlinable
    public mutating func prepend(_ element: Element) {
        _ensureUnique()
        _storage.prepend(element)
    }
    
    /// Removes and returns the first element of the deque.
    @inlinable
    @discardableResult
    public mutating func removeFirst() -> Element {
        _ensureUnique()
        return _storage.removeFirst()
    }
    
    /// Removes the first `k` elements from the deque.
    @inlinable
    public mutating func removeFirst(_ k: Int) {
        guard k > 0 else { return }
        _ensureUnique()
        _storage.removeFirst(k)
    }
    
    /// Removes and returns the last element of the deque.
    @inlinable
    @discardableResult
    public mutating func removeLast() -> Element {
        _ensureUnique()
        return _storage.removeLast()
    }
    
    /// Removes all elements from the deque.
    @inlinable
    public mutating func removeAll() {
        _ensureUnique()
        _storage.removeAll()
    }
    
    /// Ensures the storage is uniquely referenced (copy-on-write).
    @inlinable
    internal mutating func _ensureUnique() {
        if !isKnownUniquelyReferenced(&_storage) {
            _storage = _storage.copy()
        }
    }
}
    
// MARK: - Collection Conformance

extension Deque: Collection {
    @inlinable
    public var startIndex: Int { 0 }
    
    @inlinable
    public var endIndex: Int { count }

    @inlinable
    public func index(after i: Int) -> Int {
        i + 1
    }
}

extension Deque: MutableCollection {
    // Subscript already defined above
}

extension Deque: RandomAccessCollection {
    // Inherits default implementations
}

extension Deque: ExpressibleByArrayLiteral {
    @inlinable
    public init(arrayLiteral elements: Element...) {
        self.init()
        for element in elements {
            append(element)
        }
    }
}

extension Deque: Equatable where Element: Equatable {
    @inlinable
    public static func == (lhs: Deque<Element>, rhs: Deque<Element>) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for i in 0..<lhs.count {
            if lhs[i] != rhs[i] {
                return false
            }
        }
        return true
    }
}

extension Deque: Hashable where Element: Hashable {
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(count)
        for element in self {
            hasher.combine(element)
        }
    }
}

extension Deque: Codable where Element: Codable {
    @inlinable
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.init()
        while !container.isAtEnd {
            append(try container.decode(Element.self))
        }
    }
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for element in self {
            try container.encode(element)
        }
    }
}

// MARK: - Internal Storage

@usableFromInline
internal final class _DequeStorage<Element>: @unchecked Sendable {
    @usableFromInline
    internal var _buffer: UnsafeMutablePointer<Element>
    
    @usableFromInline
    internal var _capacity: Int
    
    @usableFromInline
    internal var _startIndex: Int
    
    @usableFromInline
    internal var _count: Int
    
    @inlinable
    internal init(capacity: Int = 8) {
        _capacity = max(capacity, 8)
        _buffer = UnsafeMutablePointer<Element>.allocate(capacity: _capacity)
        _startIndex = 0
        _count = 0
    }
    
    @inlinable
    internal init(copying other: _DequeStorage<Element>) {
        _capacity = other._capacity
        _buffer = UnsafeMutablePointer<Element>.allocate(capacity: _capacity)
        // Normalize layout: always start at 0 for simpler future operations
        _startIndex = 0
        _count = other._count
        
        // Copy elements, normalizing layout to start at index 0
        for i in 0..<_count {
            let srcIndex = (other._startIndex + i) % other._capacity
            _buffer.advanced(by: i).initialize(to: other._buffer[srcIndex])
        }
    }
    
    @inlinable
    internal func copy() -> _DequeStorage<Element> {
        _DequeStorage(copying: self)
    }
    
    deinit {
        // Destroy all elements
        for i in 0..<_count {
            let index = (_startIndex + i) % _capacity
            _buffer.advanced(by: index).deinitialize(count: 1)
        }
        _buffer.deallocate()
    }
    
    @inlinable
    internal var count: Int {
        _count
    }
    
    @inlinable
    internal subscript(position: Int) -> Element {
        get {
            precondition(position >= 0 && position < _count, "Index out of range")
            let index = (_startIndex + position) % _capacity
            return _buffer[index]
        }
        set {
            precondition(position >= 0 && position < _count, "Index out of range")
            let index = (_startIndex + position) % _capacity
            _buffer[index] = newValue
        }
    }
    
    @inlinable
    internal func append(_ element: Element) {
        _growIfNeeded()
        let endIndex = (_startIndex + _count) % _capacity
        _buffer.advanced(by: endIndex).initialize(to: element)
        _count += 1
    }
    
    @inlinable
    internal func prepend(_ element: Element) {
        _growIfNeeded()
        _startIndex = (_startIndex - 1 + _capacity) % _capacity
        _buffer.advanced(by: _startIndex).initialize(to: element)
        _count += 1
    }
    
    @inlinable
    internal func removeFirst() -> Element {
        precondition(_count > 0, "Cannot remove from empty deque")
        let element = _buffer[_startIndex]
        _buffer.advanced(by: _startIndex).deinitialize(count: 1)
        _startIndex = (_startIndex + 1) % _capacity
        _count -= 1
        _shrinkIfNeeded()
        return element
    }
    
    @inlinable
    internal func removeFirst(_ k: Int) {
        precondition(k >= 0 && k <= _count, "Cannot remove more elements than exist")
        guard k > 0 else { return }
        
        // Destroy removed elements
        for i in 0..<k {
            let index = (_startIndex + i) % _capacity
            _buffer.advanced(by: index).deinitialize(count: 1)
        }
        
        _startIndex = (_startIndex + k) % _capacity
        _count -= k
        _shrinkIfNeeded()
    }
    
    @inlinable
    internal func removeLast() -> Element {
        precondition(_count > 0, "Cannot remove from empty deque")
        let lastIndex = (_startIndex + _count - 1) % _capacity
        let element = _buffer[lastIndex]
        _buffer.advanced(by: lastIndex).deinitialize(count: 1)
        _count -= 1
        _shrinkIfNeeded()
        return element
    }
    
    @inlinable
    internal func removeAll() {
        // Destroy all elements
        for i in 0..<_count {
            let index = (_startIndex + i) % _capacity
            _buffer.advanced(by: index).deinitialize(count: 1)
        }
        _count = 0
        _startIndex = 0
        // Optionally shrink capacity, but keep minimum
        if _capacity > 8 {
            _buffer.deallocate()
            _capacity = 8
            _buffer = UnsafeMutablePointer<Element>.allocate(capacity: _capacity)
        }
    }
    
    @inlinable
    internal func _growIfNeeded() {
        guard _count >= _capacity else { return }
        
        let newCapacity = _capacity * 2
        let newBuffer = UnsafeMutablePointer<Element>.allocate(capacity: newCapacity)
        
        // Copy elements to new buffer starting at index 0
        for i in 0..<_count {
            let oldIndex = (_startIndex + i) % _capacity
            newBuffer.advanced(by: i).initialize(to: _buffer[oldIndex])
            _buffer.advanced(by: oldIndex).deinitialize(count: 1)
        }
    
        _buffer.deallocate()
        _buffer = newBuffer
        _capacity = newCapacity
        _startIndex = 0
    }
    
    @inlinable
    internal func _shrinkIfNeeded() {
        // Only shrink if we're using less than 1/4 of capacity and capacity > 8
        guard _capacity > 8 && _count * 4 < _capacity else { return }
        
        let newCapacity = max(8, _capacity / 2)
        let newBuffer = UnsafeMutablePointer<Element>.allocate(capacity: newCapacity)
        
        // Copy elements to new buffer
        for i in 0..<_count {
            let oldIndex = (_startIndex + i) % _capacity
            newBuffer.advanced(by: i).initialize(to: _buffer[oldIndex])
            _buffer.advanced(by: oldIndex).deinitialize(count: 1)
        }
        
        _buffer.deallocate()
        _buffer = newBuffer
        _capacity = newCapacity
        _startIndex = 0
    }
}
