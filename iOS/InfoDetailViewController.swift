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
        if MFMailComposeViewController.canSendMail() {
            let mailComposeViewController = stationFeedbackMailController()
            self.present(mailComposeViewController, animated: true, completion: nil)
        } else {
            let alert = UIAlertController(title: "Can't send mail", message: "Looks like you need to add an email address. Go to Settings.", preferredStyle: .alert)

            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
                alert.dismiss(animated: true, completion: nil)
            }))

            alert.addAction(UIAlertAction(title: "Settings", style: .default, handler: { _ in
                let settingsURL = URL(string: UIApplication.openSettingsURLString)!
                UIApplication.shared.open(settingsURL)
            }))

            present(alert, animated: true, completion: nil)
        }
    }
    
    @IBAction func dialADJ(_ sender: UIButton) {
        UIApplication.shared.open(RadioStation.WXYC.requestLine)
    }
    
    // MARK: Private
    
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

extension InfoDetailViewController: MFMailComposeViewControllerDelegate {
    private func stationFeedbackMailController() -> MFMailComposeViewController {
        let mailComposerVC = MFMailComposeViewController()
        mailComposerVC.mailComposeDelegate = self
        mailComposerVC.setToRecipients(["feedback@wxyc.org"])
        mailComposerVC.setSubject("Feedback on the WXYC app")
        return mailComposerVC
    }

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true, completion: nil)
    }
}
