//
//  URLSession+WebSession.swift
//  Core
//
//  URLSession extension conforming to WebSession protocol.
//
//  Created by Jake Bromberg on 04/16/20.
//  Copyright © 2020 WXYC. All rights reserved.
//

import Foundation

extension URLSession: WebSession {
    public func data(from url: URL) async throws -> Data {
        let (data, _) = try await data(from: url)
        return data
    }
}
