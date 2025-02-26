import UIKit
import Core
import Logger

final class RootPageViewController: UIPageViewController {
    let nowPlayingViewController = PlaylistViewController(style: .grouped)
    let infoDetailViewController = InfoDetailViewController(nibName: nil, bundle: nil)
    init() {
        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: nil
        )
    }
    
    required init?(coder: NSCoder) {
        Log(.error, "init(coder:) has not been implemented")
        fatalError( "init(coder:) has not been implemented")
    }
    
    override var transitionStyle: TransitionStyle { .scroll }
    
    // MARK: Life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setUpBackground()
        self.setUpPages()
    }
    
    private func setUpBackground() {
        let backgroundImageView = UIImageView(image: #imageLiteral(resourceName: "background"))
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(backgroundImageView, at: 0)
        view.sendSubviewToBack(backgroundImageView)
        
        view.leadingAnchor.constraint(equalTo: backgroundImageView.leadingAnchor).isActive = true
        view.trailingAnchor.constraint(equalTo: backgroundImageView.trailingAnchor).isActive = true
        view.topAnchor.constraint(equalTo: backgroundImageView.topAnchor).isActive = true
        view.bottomAnchor.constraint(equalTo: backgroundImageView.bottomAnchor).isActive = true
    }
    
    private func setUpPages() {
        self.dataSource = self
        
        self.setViewControllers(
            [self.nowPlayingViewController],
            direction: .forward,
            animated: false,
            completion: nil
        )
        
        let _ = self.infoDetailViewController.view
    }
    
    // MARK - Customization
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        viewControllers?.forEach { $0.viewWillLayoutSubviews() }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        viewControllers?.forEach { $0.viewDidLayoutSubviews() }
    }
}

extension RootPageViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        switch viewController {
        case self.nowPlayingViewController:
            return nil
        case self.infoDetailViewController:
            return self.nowPlayingViewController
        default:
            Log(.error, "Unknown view controller: \(viewController)")
            fatalError()
        }
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        switch viewController {
        case self.nowPlayingViewController:
            return self.infoDetailViewController
        case self.infoDetailViewController:
            return nil
        default:
            Log(.error, "Unknown view controller: \(viewController)")
            fatalError()
        }
    }
    
    func presentationCount(for pageViewController: UIPageViewController) -> Int {
        return 2
    }
    
    func presentationIndex(for pageViewController: UIPageViewController) -> Int {
        switch pageViewController.presentedViewController {
        case self.nowPlayingViewController:
            return 0
        case self.infoDetailViewController:
            return 1
        default:
            return 0
        }
    }
}

