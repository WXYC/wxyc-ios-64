import UniformTypeIdentifiers
import MessageUI
import Core
import UIKit

class InfoDetailViewController: UIViewController {
    @IBOutlet weak var stationDescriptionTextView: UITextView!
    @IBOutlet weak var feedbackButton: UIButton!
    @IBOutlet weak var dialADJButton: UIButton!
    
    // MARK: Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        stationDescriptionTextView.text = RadioStation.WXYC.description
        feedbackButton.setAttributedTitle(feedbackString, for: .normal)
        
        if UIApplication.shared.canOpenURL(RadioStation.WXYC.requestLine) {
            dialADJButton.setAttributedTitle(requestString, for: .normal)
        } else {
            dialADJButton.isHidden = true
        }
    }
    
    // MARK: IBActions
    
    @IBAction func feedbackButtonPressed(_ sender: UIButton) {
        self.promptForLogs()
    }
    
    @IBAction func dialADJ(_ sender: UIButton) {
        UIApplication.shared.open(RadioStation.WXYC.requestLine)
    }
    
    // MARK: Private
    
    private func promptForLogs() {
        let alert = UIAlertController(
            title: "Is this a bug?",
            message: "If you’re sending feedback because you spotted a bug, would you mind if we attached some debug logs? This will help us figure out what’s going wrong and doesn’t include any personal info.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Yes!", style: .default) { action in
            self.sendFeedback(includeLogs: true)
        })
        alert.addAction(UIAlertAction(title: "S'all good", style: .default) { action in
            self.sendFeedback(includeLogs: false)
        })
        self.present(alert, animated: true)
    }
    
    func sendFeedback(includeLogs: Bool) {
        if MFMailComposeViewController.canSendMail() {
            let mailComposeViewController = stationFeedbackMailController()
            self.present(mailComposeViewController, animated: true, completion: nil)
        } else {
            UIApplication.shared.open(feedbackURL())
        }
    }
    
    private var requestString: NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = UIImage(systemName: "phone.fill")?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        
        let requestString = NSMutableAttributedString(attachment: attachment)
        let textString = NSAttributedString(string: " Make a request")
        requestString.append(textString)
        
        return requestString
    }
    
    private var feedbackString: NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = UIImage(systemName: "envelope.fill")?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        
        let requestString = NSMutableAttributedString(attachment: attachment)
        let textString = NSAttributedString(string: " Send us feedback on the app")
        requestString.append(textString)
        
        return requestString
    }
}

extension InfoDetailViewController: @preconcurrency MFMailComposeViewControllerDelegate {
    private static let feedbackAddress = "feedback@wxyc.org"
    private static let subject = "Feedback on the WXYC app"
    
    private func stationFeedbackMailController() -> MFMailComposeViewController {
        let mailComposerVC = MFMailComposeViewController()
        mailComposerVC.mailComposeDelegate = self
        mailComposerVC.setToRecipients([Self.feedbackAddress])
        mailComposerVC.setSubject(Self.subject)
        if let (fileName, data) = Logger.fetchLogs() {
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
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        if let error {
            Log(.error, "Failed to send feedback email: \(error)")
        }
        controller.dismiss(animated: true, completion: nil)
    }
}
