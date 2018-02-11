//
//  WXYCTests.swift
//  WXYCTests
//
//  Created by Jake Bromberg on 2/11/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import XCTest
import Core

class WXYCTests: XCTestCase {
    let cache = Cache(defaults: UserDefaults())
    
    enum Key: String {
        case test
    }
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testCaching() {
        self.cache[Key.test] = 1
        XCTAssertEqual(self.cache[Key.test], 1)
    }
    
    func testLifespan() {
        self.cache[Key.test, 0] = 1
        XCTAssertEqual(self.cache[Key.test], nil as Int?)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
