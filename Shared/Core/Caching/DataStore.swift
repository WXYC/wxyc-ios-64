//
//  Defaults.swift
//  WXYC
//
//  Created by Jake Bromberg on 2/26/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import Foundation

protocol Cache {
    subscript(key: String) -> Data? { get set }
}

extension UserDefaults: Cache {
    subscript(key: String) -> Data? {
        get {
            return self.object(forKey: String(key.hashValue)) as? Data
        }
        set {
            self.set(newValue, forKey: String(key.hashValue))
        }
    }
}
