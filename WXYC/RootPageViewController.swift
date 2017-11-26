import UIKit

class RootPageViewController: UIPageViewController {
    let nowPlayingViewController: NowPlayingViewController
    let infoDetailViewController: InfoDetailViewController
    
    let nowPlayingService: NowPlayingService
    let lockscreenInfoService: LockscreenInfoService
    
    let webservice: Webservice

    required init?(coder: NSCoder) {
        nowPlayingViewController = NowPlayingViewController.loadFromNib()
        infoDetailViewController = InfoDetailViewController.loadFromNib()
        
        nowPlayingService = NowPlayingService(delegate: nowPlayingViewController)
        lockscreenInfoService = LockscreenInfoService()
        
        webservice = Webservice()

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
        
        _ = Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(self.checkPlaylist), userInfo: nil, repeats: true)
        
        self.checkPlaylist()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    @objc func checkPlaylist() {
        let playcutRequest = webservice.getCurrentPlaycut()
        playcutRequest.observe(with: self.updateWith(playcutResult:))
        
        let imageRequest = playcutRequest.getArtwork()
        imageRequest.observe(with: self.update(artworkResult:))
    }
    
    func updateWith(playcutResult result: Result<Playcut>) {
        nowPlayingService.updateWith(playcutResult: result)
        lockscreenInfoService.updateWith(playcutResult: result)
    }
    
    func update(artworkResult: Result<UIImage>) {
        nowPlayingService.update(artworkResult: artworkResult)
        lockscreenInfoService.update(artworkResult: artworkResult)
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

