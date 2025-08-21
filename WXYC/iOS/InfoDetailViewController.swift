import UniformTypeIdentifiers
import MessageUI
import Core
import UIKit
import Logger
import PostHog
import Analytics
import Secrets

class InfoDetailViewController: UIViewController {
    @IBOutlet weak var stationDescriptionTextView: UITextView!
    @IBOutlet weak var feedbackButton: UIButton!
    @IBOutlet weak var makeARequestButton: UIButton!
    @IBOutlet weak var dialADJButton: UIButton!
    
    // MARK: Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        stationDescriptionTextView.text = RadioStation.WXYC.description
        
        feedbackButton.setAttributedTitle(feedbackString, for: .normal)
        feedbackButton.layer.cornerRadius = 8
        
        makeARequestButton.setAttributedTitle(requestString, for: .normal)
        makeARequestButton.layer.cornerRadius = 8
        
        dialADJButton.setAttributedTitle(dialADJString, for: .normal)
        dialADJButton.layer.cornerRadius = 8
    }
    
    // MARK: IBActions
    
    @IBAction func feedbackButtonPressed(_ sender: UIButton) {
        self.promptForLogs()
    }
    
    var request: String = ""
    
    @IBAction func dialADJ(_ sender: UIButton) {
        UIApplication.shared.open(RadioStation.WXYC.requestLine)
    }
    
    @IBAction func sendARequest(_ sender: UIButton) {
        let alert = UIAlertController(
            title: "What would you like to request?",
            message: "Please include song title and artist.",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            self.request = textField.text ?? ""
        }

        let requestAction = UIAlertAction(title: "Request", style: .default) { action in
            Task {
                if let text = alert.textFields?.first?.text {
                    // Use the text here
                    print("User entered: \(text)")
                    try await self.sendMessageToServer(message: text)
                }
            }
        }
        alert.addAction(requestAction)
        alert.preferredAction = requestAction
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true)
    }
    
    // MARK: Private
    
    func sendMessageToServer(message: String) async throws {
        guard let url = URL(string: Secrets.slackWxycRequestsWebhook) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-type")
        
        let json: [String: Any] = ["text": message]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json) else { return }
        request.httpBody = jsonData
        
        PostHogSDK.shared.capture(
            "Request sent",
            context: "Info ViewController",
            additionalData: [
                "message": message
            ]
        )
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let response = response as? HTTPURLResponse {
                Log(.info, "Response status code: \(response.statusCode)")
            }
        } catch {
            Log(.error, "Error sending message to Slack: \(error)")
            PostHogSDK.shared.capture(error: error, context: "Info ViewController")
        }
    }
    
    private func promptForLogs() {
        let alert = UIAlertController(
            title: "Is this a bug?",
            message: "If you’re sending feedback because you spotted a bug, would you mind if we attached some debug logs? This will help us figure out what’s going wrong and doesn’t include any personal info.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Yes!", style: .default) { action in
            self.sendFeedback(attachLogs: true)
        })
        alert.addAction(UIAlertAction(title: "S'all good", style: .default) { action in
            self.sendFeedback(attachLogs: false)
        })
        self.present(alert, animated: true)
    }
    
    func sendFeedback(attachLogs: Bool) {
        if MFMailComposeViewController.canSendMail() {
            let mailComposeViewController = stationFeedbackMailController(attachLogs: attachLogs)
            self.present(mailComposeViewController, animated: true, completion: nil)
        } else {
            UIApplication.shared.open(feedbackURL())
        }
    }
    
    private var requestString: NSAttributedString {
        makeButtonString(withTitle: "Make a request", icon: "message.fill")
    }
    
    private var feedbackString: NSAttributedString {
        makeButtonString(withTitle: "Send us feedback on the app", icon: "envelope.fill")
    }
    
    private var dialADJString: NSAttributedString {
        makeButtonString(withTitle: "Dial a DJ", icon: "phone.fill")
    }
    
    func makeButtonString(withTitle title: String, icon: String) -> NSAttributedString {
        let attachment = NSTextAttachment()
        
        if let image = UIImage(systemName: icon)?.withRenderingMode(.alwaysTemplate) {
            attachment.image = image
        } else if let image = UIImage(named: icon)?.withRenderingMode(.alwaysTemplate) {
            attachment.image = image
        }
        
        let requestString = NSMutableAttributedString(attachment: attachment)
        let textString = NSAttributedString(string: " " + title)
        requestString.append(textString)
        
        return requestString
    }
}

extension InfoDetailViewController: MFMailComposeViewControllerDelegate {
    private static let feedbackAddress = "feedback@wxyc.org"
    private static let subject = "Feedback on the WXYC app"
    
    private func stationFeedbackMailController(attachLogs: Bool) -> MFMailComposeViewController {
        PostHogSDK.shared.capture("feedback email presented")
        
        let mailComposerVC = MFMailComposeViewController()
        mailComposerVC.mailComposeDelegate = self
        mailComposerVC.setToRecipients([Self.feedbackAddress])
        mailComposerVC.setSubject(Self.subject)
        if attachLogs,
           let (fileName, data) = Logger.fetchLogs() {
            let mimeType = UTType.plainText.preferredMIMEType ?? "plain/text"
            mailComposerVC.addAttachmentData(data, mimeType: mimeType, fileName: fileName)
        }
        return mailComposerVC
    }
    
    private func feedbackURL() -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.feedbackAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: Self.subject)
        ]
        
        return components.url!
    }
    
    // MARK: MFMailComposeViewControllerDelegate
    
    nonisolated func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        if let error {
            PostHogSDK.shared.capture(error: error, context: "feedbackEmail")
            Log(.error, "Failed to send feedback email: \(error)")
        } else {
            PostHogSDK.shared.capture("feedback email sent")
        }
        
        Task { @MainActor in
            controller.dismiss(animated: true, completion: nil)
        }
    }
}
