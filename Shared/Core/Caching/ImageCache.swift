//
//  ImageStore.swift
//  WXYC
//
//  Created by Jake Bromberg on 2/26/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import Foundation

final class ImageCache: Cache {
    subscript(key: String) -> Data? {
        get {
            let path = self.tempDirectory + key
            
            return FileManager.default.contents(atPath: path)
        }
        set {
            let path = self.tempDirectory + key
            guard FileManager.default.createFile(atPath: path, contents: newValue, attributes: nil) else {
                fatalError()
            }
        }
    }
    
    private let tempDirectory = NSTemporaryDirectory()
}
