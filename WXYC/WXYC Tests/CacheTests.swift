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
    let cacheCoordinator = CacheCoordinator(cache: UserDefaults())
    
    enum Key: String {
        case test
    }
    
    func testCaching() {
        self.cacheCoordinator.set(value: 1, for: Key.test, lifespan: DefaultLifespan)
    
    }
    
    func testLifespan() {
        let expectation = XCTestExpectation(description: "value expires")
        
        self.cacheCoordinator.set(value: 1, for: Key.test, lifespan: 0)
        
        let future: Future<Int> = self.cacheCoordinator.getValue(for: Key.test)
        
        future.observe { result in
            switch result {
            case .success(_):
                XCTFail()
            case .error(_):
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 1)
    }    
}
