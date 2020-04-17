import UIKit
import Core

final class RootPageViewController: UIPageViewController {
    let nowPlayingViewController = PlaylistViewController(style: .grouped)
    let infoDetailViewController = InfoDetailViewController()
    
    var pages: [UIViewController] {
        return [
            nowPlayingViewController,
            infoDetailViewController
        ]
    }
    
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
        
        view.leadingAnchor.constraint(equalTo: backgroundImageView.leadingAnchor).isActive = true
        view.trailingAnchor.constraint(equalTo: backgroundImageView.trailingAnchor).isActive = true
        view.topAnchor.constraint(equalTo: backgroundImageView.topAnchor).isActive = true
        view.bottomAnchor.constraint(equalTo: backgroundImageView.bottomAnchor).isActive = true
    }
    
    private func setUpPages() {
        self.dataSource = self
        
        self.setViewControllers(
            [nowPlayingViewController],
            direction: .forward,
            animated: false,
            completion: nil
        )
    }
    
    // MARK - Customization
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        viewControllers?.forEach({ $0.viewWillLayoutSubviews() })
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        viewControllers?.forEach({ $0.viewDidLayoutSubviews() })
    }
}

extension RootPageViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        switch viewController {
        case nowPlayingViewController:
            return nil
        case infoDetailViewController:
            return nowPlayingViewController
        default:
            fatalError()
        }
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        switch viewController {
        case nowPlayingViewController:
            return infoDetailViewController
        case infoDetailViewController:
            return nil
        default:
            fatalError()
        }
    }
    
    func presentationCount(for pageViewController: UIPageViewController) -> Int {
        return self.pages.count
    }
    
    func presentationIndex(for pageViewController: UIPageViewController) -> Int {
        return 0
    }
}

