import PostHog
import Foundation

public extension PostHogSDK {
    func capture(error: Error, context: String, additionalData: [String: String] = [:]) {
        var defaultProperties = [
            "error": "\(error)",
            "context": context
        ]
        defaultProperties.update(with: additionalData)
        
        PostHogSDK.shared.capture(
            "error",
            properties: defaultProperties)
    }
    
    func capture(_ event: String, context: String, additionalData: [String: String] = [:]) {
        var defaultProperties = ["context": context]
        defaultProperties.update(with: additionalData)

        PostHogSDK.shared.capture(
            event,
            properties: defaultProperties
        )
    }
    
    func play(_ source: Any = #function) {
        PostHogSDK.shared.capture(
            "play",
            properties: [
                "source": source
            ])
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
    mutating func update(with dict: Dictionary<Key, Value>) {
        for (key, value) in dict {
            self[key] = value
        }
    }
}
