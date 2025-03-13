import PostHog

public extension PostHogSDK {
    func capture(error: Error, context: String, additionalData: [String: String] = [:]) {
        var defaultProperties = [
            "error": "\(error)",
            "context": "feedbackEmail"
        ]
        defaultProperties.update(with: additionalData)
        
        PostHogSDK.shared.capture(
            "error",
            properties: defaultProperties)
    }
}

extension Dictionary {
    mutating func update(with dict: Dictionary<Key, Value>) {
        for (key, value) in dict {
            self[key] = value
        }
    }
}
