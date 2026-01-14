//
//  Queue.swift
//  PartyHorn
//
//  Thread-safe queue for sequencing party horn events.
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

internal struct Queue<T>: RandomAccessCollection {
    typealias Index = Array<T>.Index
    
    let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
    }
    
    subscript(position: Index) -> T {
        get {
            queue[position]
        }
    }
    
    var startIndex: Index { queue.startIndex }
    var endIndex: Index { queue.endIndex }
    
    mutating func enqueue(_ element: T) {
        queue.append(element)
        
        if queue.count > capacity {
            _ = queue.removeFirst()
        }
    }
    
    private var queue: [T] = []
}

extension Queue where Element: FloatingPoint {
    internal func sum() -> Element {
        reduce(Element.zero, +)
    }
    
    internal func average () -> Element {
        sum() / Element(count)
    }
}
