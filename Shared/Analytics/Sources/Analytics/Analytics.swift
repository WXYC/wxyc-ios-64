//
//  Analytics.swift
//  Analytics
//
//  Error types and PostHog extensions for analytics tracking.
//  Provides structured error capture with context for debugging.
//
//  Created by Jake Bromberg on 03/12/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import PostHog

protocol AnalyticsError: Error { }
    
public struct AnalyticsDecoderError: AnalyticsError {
    let description: String
    
    public init(description: String) {
        self.description = description
    }
}

public struct AnalyticsOSError: AnalyticsError {
    let domain: String
    let code: Int
    let description: String
    
    public init(domain: String, code: Int, description: String) {
        self.domain = domain
        self.code = code
        self.description = description
    }
}

public extension PostHogSDK {
    func capture(error: AnalyticsDecoderError, context: String, additionalData: [String: String] = [:]) {
        PostHogSDK.shared.capture("error", properties: [
            "error": error.localizedDescription,
            "context": context,
            "additionalData": "\(additionalData)"
        ])
    }
    
//    func setUp() {
//        let POSTHOG_API_KEY = Secrets.posthogApiKey
//        let POSTHOG_HOST = "https://us.i.posthog.com"
//        
//        let config = PostHogConfig(apiKey: POSTHOG_API_KEY, host: POSTHOG_HOST)
//        
//        PostHogSDK.shared.setup(config)
//        PostHogSDK.shared.register(["Build Configuration" : self.buildConfiguration()])
//    }
    
    func capture(error: Error, context: String, additionalData: [String: String] = [:]) {
        var defaultProperties = [
            "description": "\(error.localizedDescription)",
            "context": context
        ]
        defaultProperties.merge(with: additionalData)
        
        PostHogSDK.shared.capture(
            "error",
            properties: defaultProperties)
    }
        
    func capture(error: String, code: Int, context: String, additionalData: [String: String] = [:]) {
        var defaultProperties = [
            "description": error,
            "code": "\(code)",
            "context": context
        ]
        defaultProperties.merge(with: additionalData)
        
        PostHogSDK.shared.capture(
            "error",
            properties: defaultProperties
        )
    }
    
    func capture(error: AnalyticsOSError, context: String, additionalData: [String: String] = [:]) {
        var defaultProperties: [String : Any] = [
            "domain": error.domain,
            "code": "\(error.code)",
            "description": error.localizedDescription,
            "context": context
        ]
        defaultProperties.merge(with: additionalData)
        
        PostHogSDK.shared.capture(
            "error",
            properties: defaultProperties
        )
    }
    
    func capture(_ event: String, context: String? = nil, additionalData: [String: String] = [:]) {
        var defaultProperties = ["context": context]
        defaultProperties.merge(with: additionalData)
        
        PostHogSDK.shared.capture(
            event,
            properties: defaultProperties as [String : Any]
        )
    }
}
    
extension Dictionary {
    mutating func merge(with dict: Dictionary<Key, Value>) {
        for (key, value) in dict {
            self[key] = value
        }
    }
}
