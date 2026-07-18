//
//  OpenAPPViewController+ChatPanel.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

// MARK: - Chat Panel（接线层）
//
// BODragScroll 的尺寸、档位和滚动交接在 OpenAPPChatPanelCoordinator；
// 这里只把 ViewController 环境、键盘避让和消息通路接到 coordinator。

extension OpenAPPViewController {

    /// 初始化对话流面板：层级插在 inputBar 之下，默认半屏档。
    func setupChatPanel() {
        view.insertSubview(chatPanelCoordinator.dragScrollView, belowSubview: inputBar)
        mockChatResponder.onEvent = { [weak self] event in
            self?.handleMockChatEvent(event)
        }
    }

    /// 将当前 viewport、安全区和 inputBar 展开宽度交给 coordinator 更新固定面板几何。
    func layoutChatPanel() {
        chatPanelCoordinator.updateLayout(
            bounds: view.bounds,
            safeAreaInsets: view.safeAreaInsets,
            inputBarExpandedFrame: OpenAPPInputBarFramePolicy.preferredExpandedFrame(inputBarLayoutContext),
            bottomAvoidingInset: chatPanelBottomAvoidingInset
        )
    }

    /// 业务主动切换档位，实际动画和中途打断由 BODragScroll 管理。
    func setChatPanelDetent(_ detent: OpenAPPChatPanelDetent, animated: Bool) {
        chatPanelCoordinator.move(to: detent, animated: animated)
    }

    /// 将消息列表滚到最新一条；真实 session、mock、键盘和 inputBar 共用这一条路径。
    func scrollToBottom(animated: Bool) {
        chatPanelView.listView.scrollToBottom(animated: animated)
    }

    /// 列表底部避让：悬浮 inputBar 高度 + 安全区/键盘取大者。
    /// 面板 frame 本身不避让键盘（贴底不动），只调内容 inset 保证最新消息可见。
    func updateChatPanelListInsets() {
        chatPanelCoordinator.updateBottomAvoidingInset(chatPanelBottomAvoidingInset)
    }

    private var chatPanelBottomAvoidingInset: CGFloat {
        max(view.safeAreaInsets.bottom, observedKeyboardHeight)
            + OpenAPPInputBar.barHeight
            + 12
    }

    // MARK: - 消息通路

    /// 发送分发：UI 调试模式走模拟回路，否则走真实 session；两者使用同一个 ChatPanel 列表。
    func dispatchOutgoingMessage(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if usesMockChatResponder {
            sendMockChatMessage(trimmed)
        } else {
            sendMessage(text: trimmed)
        }
    }

    private func sendMockChatMessage(_ text: String) {
        inputBar.clearText()
        // 用户连发会打断上一条流式回复：先把残留的 streaming 占位就地定格。
        if let last = chatMessages.last,
           last.role == .assistant,
           last.status == .streaming {
            chatMessages[chatMessages.count - 1].text = last.text.isEmpty ? "…" : last.text
            chatMessages[chatMessages.count - 1].status = .complete
            chatPanelView.listView.updateLastMessage(
                text: last.text.isEmpty ? "…" : last.text,
                status: .complete
            )
        }
        let message = ChatMessage(role: .user, text: text)
        chatMessages.append(message)
        chatPanelView.listView.append(message, followLatest: false)
        // 面板收着时来了新消息，自动弹到半屏，让用户看到回复。
        if chatPanelCoordinator.isAtPeekDetent {
            setChatPanelDetent(.half, animated: true)
        }
        mockChatResponder.send(text: text)
        scrollToBottom(animated: true)
    }

    private func handleMockChatEvent(_ event: OpenAPPMockChatResponder.Event) {
        switch event {
        case .began:
            let message = ChatMessage(role: .assistant, text: "", status: .streaming)
            chatMessages.append(message)
            // sendMockChatMessage 会在同步的 began 回调返回后统一滚动，避免连续启动两次动画。
            chatPanelView.listView.append(message, followLatest: false)
        case .partial(let text):
            guard !chatMessages.isEmpty else { return }
            chatMessages[chatMessages.count - 1].text = text
            chatMessages[chatMessages.count - 1].status = .streaming
            chatPanelView.listView.updateLastMessage(text: text, status: .streaming)
        case .completed(let text):
            guard !chatMessages.isEmpty else { return }
            chatMessages[chatMessages.count - 1].text = text
            chatMessages[chatMessages.count - 1].status = .complete
            chatPanelView.listView.updateLastMessage(text: text, status: .complete)
        }
    }
}

#endif
