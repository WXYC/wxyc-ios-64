//
//  WXYCTests.swift
//  WXYCTests
//
//  Created by Jake Bromberg on 2/11/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import XCTest
@testable import Core

class WXYCTests: XCTestCase {
    let cache = Cache(defaults: UserDefaults())
    
    enum Key: String {
        case test
    }
    
    func testCaching() {
        self.cache[Key.test] = 1
    
    }
    
    func testLifespan() {
        self.cache[Key.test, 0] = 1
        XCTAssertEqual(self.cache[Key.test], nil as Int?)
    }    
}
