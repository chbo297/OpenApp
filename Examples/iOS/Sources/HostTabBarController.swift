//
//  HostTabBarController.swift
//  OpenAPPDemo
//

import UIKit

/// A minimal tab bar host that simulates a real app's window hierarchy.
/// The OpenAPP SDK's chat UI lives in its own independent overlay window
/// floating above this controller.
final class HostTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let home = HostPlaceholderViewController(label: "Host App – Home")
        home.tabBarItem = UITabBarItem(
            title: "Home",
            image: UIImage(systemName: "house"),
            selectedImage: UIImage(systemName: "house.fill")
        )

        let browse = HostPlaceholderViewController(label: "Host App – Browse")
        browse.tabBarItem = UITabBarItem(
            title: "Browse",
            image: UIImage(systemName: "magnifyingglass"),
            selectedImage: UIImage(systemName: "magnifyingglass.circle.fill")
        )

        let profile = HostPlaceholderViewController(label: "Host App – Profile")
        profile.tabBarItem = UITabBarItem(
            title: "Profile",
            image: UIImage(systemName: "person"),
            selectedImage: UIImage(systemName: "person.fill")
        )

        viewControllers = [home, browse, profile]
        selectedIndex = 0
    }
}

// MARK: - Placeholder Tab

/// A trivial view controller showing a centered label, used to make the host
/// app visually distinct from the SDK's overlay UI.
final class HostPlaceholderViewController: UIViewController {

    private let titleLabel = UILabel()
    private let labelText: String

    init(label: String) {
        self.labelText = label
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        titleLabel.text = labelText
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        view.addSubview(titleLabel)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let labelW = bounds.width - 48
        let labelH: CGFloat = 60
        titleLabel.frame = CGRect(
            x: (bounds.width - labelW) / 2,
            y: (bounds.height - labelH) / 2,
            width: labelW,
            height: labelH
        )
    }
}
