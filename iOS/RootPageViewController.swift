import UIKit
import Core

class RootPageViewController: UIPageViewController {
    let nowPlayingViewController = NowPlayingViewController.loadFromNib()
    let infoDetailViewController = InfoDetailViewController.loadFromNib()
    
    var playlistService: PlaylistService?
    let lockscreenInfoService = LockscreenInfoService()
    
    var pages: [UIViewController] {
        return [
            nowPlayingViewController,
            infoDetailViewController
        ]
    }
    
    // MARK: Life cycle

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setUpBackground()
        self.setUpPages()
        self.setUpPlaylistPolling()
    }
    
    private func setUpBackground() {
        let backgroundImageView = UIImageView(image: #imageLiteral(resourceName: "background"))
        view.insertSubview(backgroundImageView, at: 0)
        backgroundImageView.frame = view.bounds
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
    
    private func setUpPlaylistPolling() {
        self.playlistService = PlaylistService(with:
            self.nowPlayingViewController,
            self.lockscreenInfoService
        )
    }
    
    // MARK - Customization

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}

extension RootPageViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        switch viewController {
        case nowPlayingViewController:
            return nil
        default:
            return infoDetailViewController
        }
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        switch viewController {
        case nowPlayingViewController:
            return infoDetailViewController
        default:
            return nil
        }
    }
    
    func presentationCount(for pageViewController: UIPageViewController) -> Int {
        return self.pages.count
    }
    
    func presentationIndex(for pageViewController: UIPageViewController) -> Int {
        return 0
    }
}

extension UIViewController {
    static func loadFromNib() -> Self {
        let nibName = String(describing: self)
        return self.init(nibName: nibName, bundle: nil)
    }
}
