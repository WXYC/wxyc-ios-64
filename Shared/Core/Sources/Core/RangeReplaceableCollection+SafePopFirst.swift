//
//  RangeReplaceableCollection+SafePopFirst.swift
//  Core
//
//  Created by Jake Bromberg on 06/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

extension RangeReplaceableCollection {
    /// Removes the first element and returns it paired with the remaining collection.
    /// Returns `nil` if the collection is empty.
    ///
    /// Named `safePopFirst` rather than `popFirst` to avoid colliding with
    /// `Collection.popFirst()` (returning `Element?`) that some standard-library
    /// subprotocols add.
    public mutating func safePopFirst() -> (Element, Self)? {
        guard !isEmpty else { return nil }
        let first = removeFirst()
        return (first, self)
    }
}
