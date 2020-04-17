//
//  WXYCTests.swift
//  WXYCTests
//
//  Created by Jake Bromberg on 2/11/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import XCTest
import Combine
@testable import Core

class WXYCTests: XCTestCase {
    let cacheCoordinator = CacheCoordinator(cache: UserDefaults())
    var observation: Cancellable?
    
    enum Key: String {
        case test
    }
    
    func testCaching() {
        self.cacheCoordinator.set(value: 1, for: Key.test, lifespan: DefaultLifespan)
    
    }
    
    func testLifespan() {
        let expectation = XCTestExpectation(description: "value expires")
        
        self.cacheCoordinator.set(value: 1, for: Key.test, lifespan: 0)
        
        let future: AnyPublisher<Int, Error> = self.cacheCoordinator.value(for: Key.test)
        
        self.observation = future.sink { result in
            switch result {
            case .success(_):
                XCTFail()
            case .failure(_):
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 1)
    }    
}
