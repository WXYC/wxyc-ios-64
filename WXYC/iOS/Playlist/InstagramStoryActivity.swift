import UIKit

// Define a custom UIActivity subclass for Instagram Stories sharing
class InstagramStoryActivity: UIActivity {
    
    // MARK: - Activity Properties
    override var activityTitle: String? {
        return "Instagram Story"
    }
    
    override var activityImage: UIImage? {
        // Provide a custom icon for your custom Instagram activity
        return UIImage(named: "instagram_icon") // ensure this image exists in your asset catalog
    }
    
    override class var activityCategory: UIActivity.Category {
        return .share
    }
    
    // Check if Instagram is available (via URL scheme)
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        if let instagramURL = URL(string: "instagram-stories://share") {
            return UIApplication.shared.canOpenURL(instagramURL)
        }
        return false
    }
    
    // Here you can extract the required items if needed.
    override func prepare(withActivityItems activityItems: [Any]) {
        // For example, look for a UIImage or URL in the activityItems if you want to use them.
        // In this case, your app already knows what to share.
    }
    
    // Perform the Instagram sharing action
    override func perform() {
        // Prepare your payload dictionary.
        var pasteboardItems = [String: Any]()
        
        // Assume you have the following images prepared
        if let backgroundImage = UIImage(named: "backgroundImage"),
           let backgroundImageData = backgroundImage.pngData() {
            pasteboardItems["com.instagram.sharedSticker.backgroundImage"] = backgroundImageData
        }
        
        // Optional: add a sticker image overlay.
        if let stickerImage = UIImage(named: "stickerImage"),
           let stickerImageData = stickerImage.pngData() {
            pasteboardItems["com.instagram.sharedSticker.stickerImage"] = stickerImageData
        }
        
        // Optional: add a content URL (e.g., an Apple Music track link).
        pasteboardItems["com.instagram.sharedSticker.contentURL"] = "https://music.apple.com/your-track-link"
        
        // Assign your dictionary to the pasteboard
        UIPasteboard.general.items = [pasteboardItems]
        
        // Open the Instagram app via the URL scheme.
        if let instagramURL = URL(string: "instagram-stories://share") {
            UIApplication.shared.open(instagramURL, options: [:]) { success in
                // Inform the system of completion.
                self.activityDidFinish(success)
            }
        } else {
            self.activityDidFinish(false)
        }
    }
}