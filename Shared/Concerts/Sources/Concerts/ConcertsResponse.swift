//
//  ConcertsResponse.swift
//  Concerts
//
//  The paginated envelope returned by Backend-Service's `GET /concerts`
//  (`ConcertsResponse` in `wxyc-shared/api.yaml` v1.15.0). A page of concerts
//  plus the pagination cursor so the Touring Soon tab can fetch subsequent pages.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The paginated response body of `GET /concerts`.
public struct ConcertsResponse: Codable, Sendable, Equatable {

    /// This page of concerts, ordered by `starts_on` ascending.
    public let concerts: [Concert]

    /// Pagination cursor for the query.
    public let pagination: PaginationInfo

    public init(concerts: [Concert], pagination: PaginationInfo) {
        self.concerts = concerts
        self.pagination = pagination
    }
}

/// Pagination metadata accompanying a `GET /concerts` page.
///
/// `page` and `limit` are always present; `total` and `hasMore` are optional in
/// the spec, so they decode to `nil` when absent.
public struct PaginationInfo: Codable, Sendable, Equatable {

    /// 1-indexed page number.
    public let page: Int

    /// Page size (the requested `limit`).
    public let limit: Int

    /// Total matching rows across all pages, or `nil` when the server omits it.
    public let total: Int?

    /// Whether another page follows this one, or `nil` when the server omits it.
    public let hasMore: Bool?

    public init(page: Int, limit: Int, total: Int? = nil, hasMore: Bool? = nil) {
        self.page = page
        self.limit = limit
        self.total = total
        self.hasMore = hasMore
    }
}
