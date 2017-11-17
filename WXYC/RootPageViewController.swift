import UIKit

class RootPageViewController: UIPageViewController {
    let nowPlayingViewController: NowPlayingViewController
    let infoDetailViewController: InfoDetailViewController

    required init?(coder: NSCoder) {
        nowPlayingViewController = NowPlayingViewController.loadFromNib()
        infoDetailViewController = InfoDetailViewController.loadFromNib()

        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let backgroundImageView = UIImageView(image: #imageLiteral(resourceName: "background"))
        view.insertSubview(backgroundImageView, at: 0)
        backgroundImageView.frame = view.bounds

        self.setViewControllers([nowPlayingViewController],
                                direction: .forward,
                                animated: false,
                                completion: nil)

        self.dataSource = self
    }

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
}

extension UIViewController {
    static func loadFromNib() -> Self {
        let nibName = String(describing: self)
        return self.init(nibName: nibName, bundle: nil)
    }
}

