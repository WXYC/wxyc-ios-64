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
        let (data, response) = try await data(from: url)

        try (response as? HTTPURLResponse)?.validateSuccessStatus()

        return data
    }
}
