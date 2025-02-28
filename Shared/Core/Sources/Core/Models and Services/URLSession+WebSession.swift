//
//  ServiceUtilities.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/16/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation

extension URLSession: WebSession {
    func data(from url: URL) async throws -> Data {
        let (data, _) = try await data(from: url)
        return data
    }
}
