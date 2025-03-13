import PostHog

public extension PostHogSDK {
    func capture(error: Error, context: String) {
        PostHogSDK.shared.capture(
            "error",
            properties: [
                "error": "\(error)",
                "context": "feedbackEmail"
            ])
    }
}
