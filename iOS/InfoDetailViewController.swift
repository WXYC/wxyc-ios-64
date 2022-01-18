import MessageUI
import Core

class InfoDetailViewController: UIViewController {
    // MARK: Overrides
    
    override func loadView() {
        super.loadView()
        self.view.backgroundColor = .blue
//        self.view.translatesAutoresizingMaskIntoConstraints = false
        

    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let stationDescriptionTextView = UITextView()
        stationDescriptionTextView.translatesAutoresizingMaskIntoConstraints = false
        stationDescriptionTextView.text = RadioStation.WXYC.description
//        stationDescriptionTextView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        self.view.addSubview(stationDescriptionTextView)
        NSLayoutConstraint.activate([
            stationDescriptionTextView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            stationDescriptionTextView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            stationDescriptionTextView.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            stationDescriptionTextView.heightAnchor.constraint(equalToConstant: 200)
        ])

//        let feedbackButton = UIButton(configuration: .plain(), primaryAction: UIAction(handler: self.feedbackButtonPressed))
//        feedbackButton.setTitle("Send us feedback on the app", for: .normal)
//        feedbackButton.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 0.5)
//
//        self.view.addSubview(feedbackButton)
//        self.view.addConstraints([
//            feedbackButton.heightAnchor.constraint(equalToConstant: 50),
//            self.view.safeAreaLayoutGuide.leadingAnchor.constraint(equalTo: feedbackButton.leadingAnchor),
//            self.view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: feedbackButton.trailingAnchor),
//            stationDescriptionTextView.bottomAnchor.constraint(equalTo: feedbackButton.topAnchor, constant: 16),
//        ])
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    // MARK: IBActions

    func feedbackButtonPressed(_ sender: UIAction) {
        if MFMailComposeViewController.canSendMail() {
            let mailComposeViewController = stationFeedbackMailController()
            self.present(mailComposeViewController, animated: true, completion: nil)
        } else {
            let alert = UIAlertController(
                title: "Can't send mail",
                message: "Looks like you need to add an email address. Go to Settings.",
                preferredStyle: .alert
            )

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
    
    func popBack(_ sender: UIBarButtonItem) {
        self.navigationController?.popViewController(animated: true)
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
