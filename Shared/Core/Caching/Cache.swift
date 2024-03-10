//
//  Defaults.swift
//  WXYC
//
//  Created by Jake Bromberg on 2/26/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import Foundation

protocol Cache: Sendable {
    subscript(key: String) -> Data? { get set }
}

extension UserDefaults {
    static let WXYC = UserDefaults(suiteName: "org.wxyc.apps")!
}

extension UserDefaults: Cache, @unchecked Sendable {
    subscript(key: String) -> Data? {
        get {
            return self.object(forKey: key) as? Data
        }
        set {
            self.set(newValue, forKey: key)
        }
    }
}
