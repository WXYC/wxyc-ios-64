//
//  ShareViewController.swift
//  Request Share Extension
//
//  Created by Jake Bromberg on 11/24/25.
//

import UIKit

@objc(ShareViewController)
class ShareViewController: UIViewController {
    
    // MARK: - Properties
    
    private var musicTrack: MusicTrack?
    private let serviceRegistry = MusicServiceRegistry.shared
    
    // MARK: - UI Components
    
    private lazy var containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 16
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var headerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Cancel", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17)
        button.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Share Music"
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var submitButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Submit", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private lazy var artworkImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 8
        imageView.layer.masksToBounds = true
        imageView.backgroundColor = .tertiarySystemFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private lazy var trackInfoLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var serviceLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "No music link found"
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        extractMusicURLs()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        
        // Add tap gesture to dismiss when tapping outside
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
        
        // Container
        view.addSubview(containerView)
        
        // Header
        containerView.addSubview(headerView)
        headerView.addSubview(cancelButton)
        headerView.addSubview(titleLabel)
        headerView.addSubview(submitButton)
        
        // Content
        containerView.addSubview(contentStackView)
        contentStackView.addArrangedSubview(artworkImageView)
        contentStackView.addArrangedSubview(trackInfoLabel)
        contentStackView.addArrangedSubview(serviceLabel)
        
        containerView.addSubview(loadingIndicator)
        containerView.addSubview(errorLabel)
        
        NSLayoutConstraint.activate([
            // Container
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.85),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            
            // Header
            headerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 56),
            
            // Cancel button
            cancelButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            cancelButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            // Title
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            // Submit button
            submitButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            submitButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            // Content stack
            contentStackView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 24),
            contentStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            contentStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            contentStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -24),
            
            // Artwork
            artworkImageView.widthAnchor.constraint(equalToConstant: 150),
            artworkImageView.heightAnchor.constraint(equalToConstant: 150),
            
            // Loading indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            // Error label
            errorLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
        ])
        
        // Initially hide content, show loading
        contentStackView.isHidden = true
        loadingIndicator.startAnimating()
    }
    
    // MARK: - Actions
    
    @objc private func cancelTapped() {
        extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0, userInfo: nil))
    }
    
    @objc private func submitTapped() {
        guard let track = musicTrack else { return }
        
        // TODO: Implement actual submission logic here
        print("Submitting track: \(track.displayTitle)")
        print("Service: \(track.service.displayName)")
        print("URL: \(track.url.absoluteString)")
        
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    @objc private func backgroundTapped() {
        cancelTapped()
    }
    
    // MARK: - URL Extraction
    
    private func extractMusicURLs() {
        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            showError()
            return
        }
        
        for item in inputItems {
            if let attachments = item.attachments {
                for attachment in attachments {
                    if attachment.hasItemConformingToTypeIdentifier("public.url") {
                        attachment.loadItem(forTypeIdentifier: "public.url", options: nil) { [weak self] (data, error) in
                            guard let self = self else { return }
                            
                            if let error = error {
                                print("Error loading URL: \(error)")
                                DispatchQueue.main.async {
                                    self.showError()
                                }
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
                            } else {
                                DispatchQueue.main.async {
                                    self.showError()
                                }
                            }
                        }
                        return
                    }
                }
            }
            
            if let text = item.attributedContentText?.string ?? item.attributedTitle?.string,
               let url = extractURL(from: text) {
                processURL(url)
                return
            }
        }
        
        showError()
    }
    
    private func extractURL(from text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        return matches?.first.flatMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return URL(string: String(text[range]))
        }
    }
    
    private func processURL(_ url: URL) {
        guard var track = serviceRegistry.parse(url: url) else {
            showError()
            return
        }
        
        self.musicTrack = track
        
        // Update UI with track info
        titleLabel.text = track.service.displayName
        trackInfoLabel.text = track.displayTitle
        serviceLabel.text = "via \(track.service.displayName)"
        
        // Show content
        loadingIndicator.stopAnimating()
        contentStackView.isHidden = false
        submitButton.isEnabled = true
        
        // Fetch artwork asynchronously
        Task {
            await fetchArtwork(for: track)
        }
    }
    
    private func fetchArtwork(for track: MusicTrack) async {
        guard let service = serviceRegistry.identifyService(for: track.url) else { return }
        
        do {
            if let artworkURL = try await service.fetchArtwork(for: track) {
                let (data, _) = try await URLSession.shared.data(from: artworkURL)
                
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        self.artworkImageView.image = image
                        self.musicTrack?.artworkURL = artworkURL
                    }
                }
            }
        } catch {
            print("Failed to fetch artwork: \(error)")
        }
    }
    
    private func showError() {
        loadingIndicator.stopAnimating()
        contentStackView.isHidden = true
        errorLabel.isHidden = false
        submitButton.isEnabled = false
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ShareViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only handle taps outside the container
        let location = touch.location(in: view)
        return !containerView.frame.contains(location)
    }
}
