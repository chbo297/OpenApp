//
//  SceneDelegate.swift
//  OpenAPPDemo
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    var agent: AIAgent?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        Logger.isEnabled = true
        Logger.minimumLevel = .debug

        let chatVC = ChatViewController()
        chatVC.title = "OpenAPP Demo"
        let navController = UINavigationController(rootViewController: chatVC)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navController
        window.makeKeyAndVisible()
        self.window = window

        Task { @MainActor in
            guard DemoConfig.loaded != nil else {
                showAlert(
                    on: chatVC,
                    title: "缺少配置文件",
                    message: "未找到 config.json。\n\n请在 Resources/ 目录下执行:\ncp config.json.example config.json\n然后填入你的配置并重新运行。"
                )
                return
            }

            // Register all providers from config into ModelProviderCentral
            for entry in DemoConfig.allProviders {
                await ModelProviderCentral.`default`.register(
                    name: entry.name,
                    provider: entry.provider
                )
            }

            let agentProfile = AIAgentProfile(
                identity: "You are a helpful AI assistant.",
                additionalPromptBuilders: [
                    PromptBuilder("Be concise and helpful."),
                    PromptBuilder("If unsure, say so honestly.")
                ]
            )

            let agent = await AIAgentCentral.default.create(
                name: "main",
                profile: agentProfile,
                modelPolicy: DemoConfig.modelPolicy,
                sessionStorage: InMemorySessionStorage()
            )
            self.agent = agent

            let chatSession = await agent.createSession(title: "Chat")
            chatVC.agent = agent
            chatVC.switchSession(to: chatSession.id)
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Persist all sessions when going to background
        Task {
            try? await agent?.sessionManager.saveAll()
        }
    }

    private func showAlert(on viewController: UIViewController, title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        viewController.present(alert, animated: true)
    }
}
