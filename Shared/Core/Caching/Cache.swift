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
    
    func allRecords() -> any Sequence<(String, Data)>
}

struct UserDefaultsCache: Cache {
    private func userDefaults() -> UserDefaults { .standard }
    
    func object(for key: String) -> Data? {
        self.userDefaults().object(forKey: key) as? Data
    }
    
    func set(object: Data?, for key: String) {
        self.userDefaults().set(object, forKey: key)
    }
    
    func allRecords() -> any Sequence<(String, Data)> {
        EmptyCollection()
    }
}

struct StandardCache: Cache, @unchecked Sendable {
    private let cache = NSCache<NSString, NSData>()
    
    func object(for key: String) -> Data? {
        if let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let fileName = cacheDirectory.appendingPathComponent(key)
            return try? Data(contentsOf: fileName)
        } else {
            print("Failed to find Cache Directory, trying NSCache.")
            let data: NSData? = self.cache.object(forKey: key as NSString)
            return data as? Data
        }
    }
    
    func set(object: Data?, for key: String) {
        if let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let fileName = cacheDirectory.appendingPathComponent(key)
            if let object {
                FileManager.default.createFile(atPath: fileName.path(), contents: object)
            } else {
                do {
                    try FileManager.default.removeItem(at: fileName)
                } catch {
                    print("Failed to remove \(fileName) from disk: \(error)")
                }
            }
        } else {
            print("Failed to find Cache Directory, trying NSCache.")
            if let object = object as? NSData {
                self.cache.setObject(object, forKey: key as NSString)
            } else {
                print("Failed to convert object to NSData, removing old object from cache.")
                self.cache.removeObject(forKey: key as NSString)
            }
        }
    }
    
    func allRecords() -> any Sequence<(String, Data)> {
        guard let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let contents = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            print("Failed to find Cache Directory, trying NSCache.")
            return EmptyCollection()
        }
        var contentsIterator = contents.makeIterator()
        let iterator = AnyIterator {
            if let fileURL = contentsIterator.next(),
               let data = try? Data(contentsOf: fileURL)
            {
                let fileName = fileURL.lastPathComponent
                return (fileName, data)
            } else {
                return nil
            }
        }
        return AnySequence(iterator)
    }
}
