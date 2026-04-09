//
//  SceneDelegate.swift
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }

        // Set a reasonable default window size on Mac Catalyst
        #if targetEnvironment(macCatalyst)
        ws.sizeRestrictions?.minimumSize = CGSize(width: 520, height: 820)
        ws.sizeRestrictions?.maximumSize = CGSize(width: 720, height: 1200)
        if let titlebar = ws.titlebar {
            titlebar.titleVisibility = .visible
        }
        #endif

        let window = UIWindow(windowScene: ws)
        window.rootViewController = UINavigationController(rootViewController: ViewController())
        self.window = window
        window.makeKeyAndVisible()
    }
}
