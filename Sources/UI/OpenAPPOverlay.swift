//
//  OpenAPPOverlay.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

/// Single entry point for hosts that want OpenAPP's chat UI as an overlay window
/// floating above their own `UIWindow` hierarchy.
///
/// `OpenAPPOverlay` owns a passthrough `OpenAPPWindow` plus an
/// `OpenAPPViewController`. The overlay window does not steal key status from
/// the host; it auto-promotes to key only when the input bar's text field
/// becomes first responder.
@MainActor
public final class OpenAPPOverlay {

    // MARK: - Public Properties

    /// The passthrough window mounted above the host's window.
    public let window: OpenAPPWindow

    /// The chat view controller hosted inside `window`.
    public let viewController: OpenAPPViewController

    // MARK: - Factories

    /// Create the overlay window in `windowScene` without binding any agent.
    /// The window becomes visible immediately; use `bind(agent:sessionId:)` later.
    @discardableResult
    public static func attach(in windowScene: UIWindowScene) -> OpenAPPOverlay {
        OpenAPPOverlay(windowScene: windowScene)
    }

    /// Create the overlay window, create a fresh session on `agent`, bind it, return.
    @discardableResult
    public static func start(
        in windowScene: UIWindowScene,
        agent: AIAgent,
        sessionTitle: String = "Chat"
    ) async -> OpenAPPOverlay {
        let overlay = OpenAPPOverlay(windowScene: windowScene)
        let session = await agent.createSession(title: sessionTitle)
        overlay.bind(agent: agent, sessionId: session.id)
        return overlay
    }

    // MARK: - Init

    private init(windowScene: UIWindowScene) {
        let viewController = OpenAPPViewController()
        self.viewController = viewController
        self.window = OpenAPPWindow(
            windowScene: windowScene,
            rootViewController: viewController
        )
    }

    // MARK: - Binding

    /// Bind an agent + existing session id to the chat view controller.
    public func bind(agent: AIAgent, sessionId: String) {
        viewController.agent = agent
        viewController.switchSession(to: sessionId)
    }

    // MARK: - Visibility

    public func show() {
        window.isHidden = false
    }

    public func hide() {
        window.isHidden = true
    }
}

#endif
