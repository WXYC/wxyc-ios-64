//
//  Defaults.swift
//  WXYC
//
//  Created by Jake Bromberg on 2/26/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import Foundation
import Logger

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
            do {
                return try Data(contentsOf: fileName)
            } catch {
                Log(.error, "Failed to read file \(fileName): \(error)")
                return nil
            }
        } else {
            Log(.error, "Failed to find Cache Directory, trying NSCache.")
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
                    Log(.error, "Failed to remove \(fileName) from disk: \(error)")
                }
            }
        } else {
            Log(.error, "Failed to find Cache Directory, trying NSCache.")
            if let object = object as? NSData {
                self.cache.setObject(object, forKey: key as NSString)
            } else {
                Log(.error, "Failed to convert object to NSData, removing old object from cache.")
                self.cache.removeObject(forKey: key as NSString)
            }
        }
    }
    
    func allRecords() -> any Sequence<(String, Data)> {
        let contents: [URL]
        do {
            guard let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                Log(.error, "Failed to find Cache Directory.")
                return EmptyCollection()
            }
            contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        } catch {
            Log(.error, "Failed to read Cache Directory: \(error.localizedDescription)")
            return EmptyCollection()
        }
        
        var contentsIterator = contents.makeIterator()
        let iterator = AnyIterator<(String, Data)> {
            guard let fileURL = contentsIterator.next() else { return nil }
            do {
                let data = try Data(contentsOf: fileURL)
                let fileName = fileURL.lastPathComponent
                return (fileName, data)
            } catch {
                Log(.error, "Failed to read data at \(fileURL): \(error.localizedDescription)")
                return nil
            }
        }
            
        return AnySequence(iterator)
    }
}
