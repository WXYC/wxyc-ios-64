//
//  Defaults.swift
//  WXYC
//
//  Created by Jake Bromberg on 2/26/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import Foundation
import Logger
import PostHog
import Analytics

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

public extension UserDefaults {
    nonisolated(unsafe) static let wxyc = UserDefaults(suiteName: "group.wxyc.iphone")!
}

struct StandardCache: Cache, @unchecked Sendable {
    struct StandardCacheError: Error, ExpressibleByStringLiteral, CustomStringConvertible {
        let message: String
        
        var description: String { message }
        
        init(stringLiteral value: String) {
            self.message = value
        }
    }
    
    private let cache = NSCache<NSString, NSData>()
    
    func object(for key: String) -> Data? {
        if let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let fileName = cacheDirectory.appendingPathComponent(key)
            do {
                return try Data(contentsOf: fileName)
            } catch {
                Log(.error, "Failed to read file \(fileName): \(error)")
                PostHogSDK.shared.capture(error: error, context: "StandardCache object(forKey:): failed to read file")
                return nil
            }
        } else {
            let error: StandardCacheError = "Failed to find Cache Directory, trying NSCache."
            Log(.error, error.description)
            PostHogSDK.shared.capture(error: error, context: "StandardCache object(forKey:): failed to find Cache Directory")
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
            let error: StandardCacheError = "Failed to find Cache Directory, trying NSCache."
            Log(.error, error.description)
            PostHogSDK.shared.capture(error: error, context: "StandardCache set(object:for:)")
            if let object = object as? NSData {
                self.cache.setObject(object, forKey: key as NSString)
            } else {
                let error: StandardCacheError = "Failed to convert object to NSData, removing old object from cache."
                Log(.error, error.description)
                PostHogSDK.shared.capture(error: error, context: "StandardCache set(object:for:)")
                self.cache.removeObject(forKey: key as NSString)
            }
        }
    }
    
    func allRecords() -> any Sequence<(String, Data)> {
        let contents: [URL]
        do {
            guard let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                let error: StandardCacheError = "Failed to find Cache Directory."
                Log(.error, error.description)
                PostHogSDK.shared.capture(error: error, context: "StandardCache set(object:for:)")
                return EmptyCollection()
            }
            contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        } catch {
            Log(.error, "Failed to read Cache Directory: \(error.localizedDescription)")
            PostHogSDK.shared.capture(error: error, context: "StandardCache allRecords")
            
            return EmptyCollection()
        }
        
        var contentsIterator = contents
            .filter { FileManager.default.isReadableFile(atPath: $0.absoluteString) }
            .makeIterator()
        let iterator = AnyIterator<(String, Data)> {
            guard let fileURL = contentsIterator.next() else { return nil }
            do {
                let data = try Data(contentsOf: fileURL)
                let fileName = fileURL.lastPathComponent
                return (fileName, data)
            } catch {
                Log(.error, "Failed to read data at \(fileURL): \(error.localizedDescription)")
                PostHogSDK.shared.capture(error: error, context: "StandardCache allRecords")
                
                return nil
            }
        }
            
        return AnySequence(iterator)
    }
}
