//
//  ShareViewController.swift
//  Request Share Extension
//
//  Created by Jake Bromberg on 11/24/25.
//

import UIKit
import Social

class ShareViewController: SLComposeServiceViewController {
    
    private var musicTrack: MusicTrack?
    private let serviceRegistry = MusicServiceRegistry.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        extractMusicURLs()
    }
    
    override func isContentValid() -> Bool {
        // Content is valid if we have a music track
        return musicTrack != nil
    }
    
    override func didSelectPost() {
        // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.
        
        guard let track = musicTrack else {
            self.extensionContext!.cancelRequest(withError: NSError(domain: "ShareExtension", code: 1, userInfo: [NSLocalizedDescriptionKey: "No music track found"]))
            return
        }
        
        // TODO: Implement actual submission logic here
        // For now, just log the track information
        print("Submitting track: \(track.displayTitle)")
        print("Service: \(track.service.displayName)")
        print("URL: \(track.url.absoluteString)")
        if let message = contentText, !message.isEmpty {
            print("Message: \(message)")
        }
    
        // Inform the host that we're done, so it un-blocks its UI. Note: Alternatively you could call super's -didSelectPost, which will similarly complete the extension context.
        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    override func didSelectCancel() {
        // User cancelled - just complete the request
        self.extensionContext!.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0, userInfo: nil))
    }

    override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return []
    }
    
    // MARK: - Private Methods
    
    private func extractMusicURLs() {
        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            return
        }
        
        for item in inputItems {
            // Check for URL attachments
            if let attachments = item.attachments {
                for attachment in attachments {
                    // Try to load as URL
                    if attachment.hasItemConformingToTypeIdentifier("public.url") {
                        attachment.loadItem(forTypeIdentifier: "public.url", options: nil) { [weak self] (data, error) in
                            guard let self = self else { return }
                            
                            if let error = error {
                                print("Error loading URL: \(error)")
                                return
                            }
                            
                            if let url = data as? URL {
                                DispatchQueue.main.async {
                                    self.processURL(url)
                                }
                            } else if let urlString = data as? String, let url = URL(string: urlString) {
                                DispatchQueue.main.async {
                                    self.processURL(url)
                                }
                            }
                        }
                    }
                }
            }
            
            // Also check for text content that might contain URLs
            if let text = item.attributedContentText?.string ?? item.attributedTitle?.string {
                if let url = extractURL(from: text) {
                    processURL(url)
                }
            }
        }
    }
    
    private func extractURL(from text: String) -> URL? {
        // Simple URL detection in text
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        return matches?.first.flatMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return URL(string: String(text[range]))
        }
    }
    
    private func processURL(_ url: URL) {
        guard let track = serviceRegistry.parse(url: url) else {
            // Not a recognized music service URL
            return
        }
        
        self.musicTrack = track
        
        // Update the placeholder text to show track info
        placeholder = "Add a message (optional)"
        
        // Update the title to show the service
        title = track.service.displayName
        
        // Reload to update validation state
        reloadConfigurationItems()
        validateContent()
    }
}

