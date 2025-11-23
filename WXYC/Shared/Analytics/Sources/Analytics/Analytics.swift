import PostHog
import Foundation

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
    
    func capture(error: NSError, context: String) {
        PostHogSDK.shared.capture(
            "error",
            properties: [
                "domain": error.domain,
                "code": "\(error.code)",
                "description": error.localizedDescription,
                "context": context
            ])
    }
    
    func capture(_ event: String, context: String? = nil, additionalData: [String: String] = [:]) {
        var defaultProperties = ["context": context]
        defaultProperties.merge(with: additionalData)

        PostHogSDK.shared.capture(
            event,
            properties: defaultProperties as [String : Any]
        )
    }
    
    func play(_ source: Any = #function, reason: String) {
        PostHogSDK.shared.capture(
            "play",
            properties: [
                "source": source,
                "reason": reason,
            ])
    }
    
    func pause(_ source: Any = #function, duration: TimeInterval) {
        PostHogSDK.shared.capture(
            "pause",
            properties: [
                "source": source,
                "duration": duration,
            ])
    }
    
    func pause(_ source: Any = #function, duration: TimeInterval, reason: String) {
        PostHogSDK.shared.capture(
            "pause",
            properties: [
                "source": source,
                "duration": duration,
                "reason": reason,
            ])
    }
}

extension Dictionary {
    mutating func merge(with dict: Dictionary<Key, Value>) {
        for (key, value) in dict {
            self[key] = value
        }
    }
}
