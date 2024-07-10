//
//  Defaults.swift
//  WXYC
//
//  Created by Jake Bromberg on 2/26/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import Foundation

protocol Cache: Sendable {
    func object(for key: String) -> Data?
    
    func set(object: Data?, for key: String)
}

struct UserDefaultsCache: Cache {
    private func userDefaults() -> UserDefaults { .standard }
    
    func object(for key: String) -> Data? {
        self.userDefaults().object(forKey: key) as? Data
    }
    
    func set(object: Data?, for key: String) {
        self.userDefaults().set(object, forKey: key)
    }
}

struct StandardCache: Cache, @unchecked Sendable {
    private let cache = NSCache<NSString, NSData>()
    
    func object(for key: String) -> Data? {
        let data: NSData? = self.cache.object(forKey: key as NSString)
        return data as? Data
    }
    
    func set(object: Data?, for key: String) {
        if let object = object as? NSData {
            self.cache.setObject(object, forKey: key as NSString)
        } else {
            self.cache.removeObject(forKey: key as NSString)
        }
    }
}
