//
//  ServiceUtilities.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/16/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation

extension URLSession: WebSession {
    func request(url: URL) -> Future<Data> {
        print(url)
        let promise = Promise<Data>()
        
        let task = dataTask(with: url) { data, _, error in
            if let error = error {
                print(url, error)
                promise.reject(with: error)
            } else {
                promise.resolve(with: data ?? Data())
            }
        }
        
        task.resume()
        
        return promise
    }
}
