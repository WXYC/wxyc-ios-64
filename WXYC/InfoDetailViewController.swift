import MessageUI

class InfoDetailViewController: UIViewController {
    @IBOutlet weak var stationLongDescTextView: UITextView!
    @IBOutlet weak var feedbackButton: UIButton!
    
    var currentStation: RadioStation?
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    // MARK: Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        stationLongDescTextView.text = currentStation?.longDesc
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
                let settingsURL = URL(string: UIApplicationOpenSettingsURLString)!
                UIApplication.shared.open(settingsURL)
            }))

            present(alert, animated: true, completion: nil)
        }
    }
    
    @IBAction func popBack(_ sender: UIBarButtonItem) {
        self.navigationController?.popViewController(animated: true)
    }
}

extension InfoDetailViewController: MFMailComposeViewControllerDelegate {
    private func stationFeedbackMailController() -> MFMailComposeViewController {
        let mailComposerVC = MFMailComposeViewController()
        mailComposerVC.mailComposeDelegate = self
        mailComposerVC.setToRecipients(["dvd@wxyc.org"])
        mailComposerVC.setSubject("Feedback on the WXYC app")
        return mailComposerVC
    }

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true, completion: nil)
    }
}
