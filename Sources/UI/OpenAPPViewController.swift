//
//  OpenAPPViewController.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

/// Main view controller for OpenAPP chat interface.
/// Hosts a message list (tableView) and an input bar (OpenAPPInputBar).
/// Intended to be used as the rootViewController of an `OpenAPPWindow`.
/// All layout is done via manual frames in `viewDidLayoutSubviews`.
open class OpenAPPViewController: UIViewController {

    // MARK: - Public API

    /// The agent powering this chat.
    public var agent: AIAgent?

    /// The currently displayed session ID.
    public private(set) var currentSessionId: String?

    /// Convenience: the current session object.
    public var currentSession: AISession? {
        guard let id = currentSessionId else { return nil }
        return agent?.session(id: id)
    }

    /// Switch to a different session.
    public func switchSession(to sessionId: String) {
        currentStreamTask?.cancel()
        currentStreamTask = nil
        currentSession?.uiState.onChange = nil
        currentSessionId = sessionId
        reloadFromSession()
        bindUIState()
    }

    // MARK: - Subviews

    public let tableView = UITableView()
    public let inputBar = OpenAPPInputBar()

    // MARK: - Data

    private var chatMessages: [ChatMessage] = []
    private var currentStreamTask: Task<Void, Never>?
    private var keyboardHeight: CGFloat = 0
    private var inputBarExpandedWidth: CGFloat = 0
    private var inputBarCollapseDelta: CGFloat = 0
    /// Tracks `view.bounds.size` to clamp collapse delta when the host size changes.
    private var inputBarHostViewBoundsSize: CGSize?

    // MARK: - Input bar collapse pan state

    private enum InputBarCollapsePanAxis {
        case undecided
        case horizontal
        case menuExpand
    }

    private var collapsePanAxis: InputBarCollapsePanAxis = .undecided
    private var collapsePanAnchorTranslation: CGPoint = .zero
    private var collapsePanAnchorDelta: CGFloat = 0
    private var collapseTranslationAtHorizontalLock: CGPoint?
    private var menuExpandAnchorTranslation: CGPoint = .zero
    private var menuExpandAnchorDelta: CGFloat = 0
    private var collapsePanBeganInCollapsedMenu: Bool = false

    private lazy var inputBarCollapsePan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleInputBarCollapsePan(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = self
        return pan
    }()

    private var inputBarMaxCollapseDelta: CGFloat {
        max(0, inputBarExpandedWidth - OpenAPPInputBar.collapsedMinWidth)
    }

    // MARK: - Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        setupTableView()
        setupInputBar()
        setupKeyboardObservers()

        reloadFromSession()
        bindUIState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        currentSession?.uiState.onChange = nil
    }

    // MARK: - Manual Frame Layout

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutInputBar()
    }

    private func layoutInputBar() {
        let b = view.bounds
        let W0 = max(0, b.width - OpenAPPInputBar.horizontalInset * 2)
        inputBarExpandedWidth = W0
        inputBar.expandedContentWidth = W0

        if inputBarHostViewBoundsSize != b.size {
            inputBarHostViewBoundsSize = b.size
            let cap = inputBarMaxCollapseDelta
            inputBarCollapseDelta = min(max(0, inputBarCollapseDelta), cap)
        }

        let w = W0 - inputBarCollapseDelta
        let x = OpenAPPInputBar.horizontalInset + W0 - w
        let barH = OpenAPPInputBar.barHeight
        let safeBottom = view.safeAreaInsets.bottom
        let originY: CGFloat
        if keyboardHeight > 0 {
            originY = b.height - keyboardHeight - barH
        } else {
            originY = b.height - barH - safeBottom
        }

        inputBar.frame = CGRect(x: x, y: originY, width: w, height: barH)
        layoutTableView()
    }

    private func layoutTableView() {
        let bounds = view.bounds
        let safeTop = view.safeAreaInsets.top
        let tableY = safeTop
        let tableH = max(0, inputBar.frame.minY - tableY)
        tableView.frame = CGRect(x: 0, y: tableY, width: bounds.width, height: tableH)
    }

    private func setInputBarCollapsed(_ collapsed: Bool, animated: Bool) {
        let cap = inputBarMaxCollapseDelta
        guard cap > 0 else { return }
        let target: CGFloat = collapsed ? cap : 0
        guard abs(inputBarCollapseDelta - target) > 0.5 else { return }
        let apply = {
            self.inputBarCollapseDelta = target
            self.layoutInputBar()
            self.inputBar.setNeedsLayout()
            self.inputBar.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.32, delay: 0, options: [.curveEaseInOut], animations: apply)
        } else {
            apply()
        }
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.keyboardDismissMode = .interactive
        tableView.backgroundColor = .systemBackground
        tableView.register(ChatMessageCell.self, forCellReuseIdentifier: ChatMessageCell.reuseIdentifier)
        view.addSubview(tableView)
    }

    private func setupInputBar() {
        inputBar.delegate = self
        inputBar.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(inputBar)
        inputBar.addGestureRecognizer(inputBarCollapsePan)
    }

    // MARK: - Keyboard

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
        else { return }

        let kbInView = view.convert(endFrame, from: nil)
        let newKeyboardH = max(0, view.bounds.intersection(kbInView).height)

        keyboardHeight = newKeyboardH

        UIView.animate(withDuration: duration) {
            self.layoutInputBar()
        }

        scrollToBottom(animated: true)
    }

    // MARK: - Session ↔ UI

    /// Reload chatMessages from the current session's message history.
    public func reloadFromSession() {
        guard let session = currentSession else {
            chatMessages = []
            if isViewLoaded { tableView.reloadData() }
            return
        }

        chatMessages = session.messages.map { Self.toChatMessage($0) }

        if session.isRunning {
            let streamText = session.uiState.streamingText
            chatMessages.append(ChatMessage(role: .assistant, text: streamText, status: .streaming))
        }

        if isViewLoaded {
            tableView.reloadData()
            scrollToBottom(animated: false)
        }
    }

    /// Convert an AIAgentMessage to a UI ChatMessage.
    public static func toChatMessage(_ msg: AIAgentMessage) -> ChatMessage {
        let role: ChatMessage.Role = msg.role == .user ? .user : .assistant
        var text = msg.text
        var toolInfo: String?

        let calls = msg.toolCalls
        if !calls.isEmpty {
            let names = calls.map { $0.name }.joined(separator: ", ")
            toolInfo = "Tools: \(names)"
            if text.isEmpty {
                text = "[Tool call: \(names)]"
            }
        }

        let results = msg.content.compactMap { content -> String? in
            if case .toolResult(let r) = content {
                let preview = r.content.prefix(100)
                return "Result: \(preview)\(r.content.count > 100 ? "..." : "")"
            }
            return nil
        }
        if !results.isEmpty && text.isEmpty {
            text = results.joined(separator: "\n")
        }

        return ChatMessage(role: role, text: text, toolInfo: toolInfo)
    }

    // MARK: - UI State Binding

    private func bindUIState() {
        guard let session = currentSession else { return }
        session.uiState.onChange = { [weak self] key in
            Task { @MainActor [weak self] in
                self?.handleUIStateChange(key: key)
            }
        }
    }

    private func handleUIStateChange(key: String) {
        guard let session = currentSession else { return }
        switch key {
        case "streamingText":
            guard !chatMessages.isEmpty,
                  chatMessages[chatMessages.count - 1].status == .streaming else { return }
            chatMessages[chatMessages.count - 1].text = session.uiState.streamingText
            let indexPath = IndexPath(row: chatMessages.count - 1, section: 0)
            tableView.reloadRows(at: [indexPath], with: .none)
            scrollToBottom(animated: false)

        case "isStreaming":
            if !session.uiState.isStreaming {
                reloadFromSession()
                inputBar.setInputEnabled(true)
            }

        case "lastError":
            if let error = session.uiState.lastError {
                guard !chatMessages.isEmpty,
                      chatMessages[chatMessages.count - 1].role == .assistant else { return }
                chatMessages[chatMessages.count - 1].text = "Error: \(error.localizedDescription)"
                chatMessages[chatMessages.count - 1].status = .error
                let indexPath = IndexPath(row: chatMessages.count - 1, section: 0)
                tableView.reloadRows(at: [indexPath], with: .none)
                inputBar.setInputEnabled(true)
            }

        default:
            break
        }
    }

    // MARK: - Send

    private func sendMessage(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let session = currentSession else { return }

        inputBar.clearText()
        inputBar.setInputEnabled(false)

        chatMessages.append(ChatMessage(role: .user, text: trimmed))
        chatMessages.append(ChatMessage(role: .assistant, text: "", status: .streaming))
        tableView.reloadData()
        scrollToBottom(animated: true)

        let stream = session.sendMessage(trimmed)
        currentStreamTask = Task { @MainActor in
            for await _ in stream {
                // Events are handled via uiState.onChange binding
            }
        }
    }

    // MARK: - Helpers

    private func scrollToBottom(animated: Bool) {
        guard !chatMessages.isEmpty else { return }
        let indexPath = IndexPath(row: chatMessages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }

    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(hi, max(lo, v))
    }
}

// MARK: - Input Bar Pan

/// Horizontal collapse/expand and menu-drag-to-expand live here — not on `OpenAPPInputBar`.
/// Vertical keyboard dismiss stays on the bar (`keyboardDismissPan`).
///
/// 松手吸附（横向拖拽，正速度 = 向右 = 收起方向）：
/// 1. 向右足够快 → 完全收起（阈值低于展开，便于轻滑收起）
/// 2. 向左足够快 → 完全展开
/// 3. 极慢 / 静止 → 仅看位置：收起超过 1/2 则收起，否则展开
extension OpenAPPViewController {

    /// 横向位移超过此值（pt）即锁定为收起手势（便于轻滑）。
    private static let inputBarCollapseAxisLockThreshold: CGFloat = 6
    /// 横向分量占优比例（|dx| vs |dy|）。
    private static let inputBarCollapseHorizontalDominance: CGFloat = 0.55

    /// 向右甩动超过此速度（pt/s）→ 收起。
    private static let inputBarCollapseFastVelocityRight: CGFloat = 180
    /// 向左甩动超过此速度（pt/s）→ 展开。
    private static let inputBarCollapseFastVelocityLeft: CGFloat = 280
    /// |vx| 低于此值视为极慢 / 静止，只按 1/2 位置判定。
    private static let inputBarCollapseStationaryVelocity: CGFloat = 50

    /// 惯性投影系数（秒）：松手后「预测落点 = 当前位置 + 速度 × 系数」。
    /// 直觉上约等于「凭手指惯性还会再滑动多久」。越大越容易顺着甩的方向完成。
    private static let inputBarCollapseProjectionFactor: CGFloat = 0.18

    /// 将横向位移同步到 `inputBarCollapseDelta`（正位移 = 向右 = 收起）。
    private func syncHorizontalCollapseDeltaFromPan(_ gr: UIPanGestureRecognizer, useFullTranslationFromBegan: Bool = false) {
        let cap = inputBarMaxCollapseDelta
        guard cap > 0 else { return }
        let t = gr.translation(in: inputBar)
        let deltaX: CGFloat
        if useFullTranslationFromBegan || collapseTranslationAtHorizontalLock == nil {
            deltaX = t.x - collapsePanAnchorTranslation.x
        } else if let lockT = collapseTranslationAtHorizontalLock {
            deltaX = t.x - lockT.x
        } else {
            deltaX = t.x - collapsePanAnchorTranslation.x
        }
        if inputBarCollapseDelta >= cap - 0.5, deltaX >= 0 { return }
        inputBarCollapseDelta = Self.clamp(collapsePanAnchorDelta + deltaX, 0, cap)
        layoutInputBar()
        inputBar.setNeedsLayout()
    }

    private func isHorizontalCollapsePan(
        translationFromBegan tFromAnchor: CGPoint,
        velocityInView v: CGPoint
    ) -> Bool {
        let ax = abs(tFromAnchor.x)
        let ay = abs(tFromAnchor.y)
        if ax < Self.inputBarCollapseAxisLockThreshold, ay < Self.inputBarCollapseAxisLockThreshold {
            return abs(v.x) > abs(v.y) && abs(v.x) > Self.inputBarCollapseStationaryVelocity
        }
        return ax >= ay * Self.inputBarCollapseHorizontalDominance
    }

    private func applyProvisionalHorizontalCollapseDelta(translationFromBegan tFromAnchor: CGPoint) {
        let cap = inputBarMaxCollapseDelta
        guard cap > 0, tFromAnchor.x != 0 else { return }
        if inputBarCollapseDelta >= cap - 0.5, tFromAnchor.x >= 0 { return }
        inputBarCollapseDelta = Self.clamp(collapsePanAnchorDelta + tFromAnchor.x, 0, cap)
        layoutInputBar()
        inputBar.setNeedsLayout()
    }

    @objc private func handleInputBarCollapsePan(_ gr: UIPanGestureRecognizer) {
        let t = gr.translation(in: inputBar)
        let tFromAnchor = CGPoint(x: t.x - collapsePanAnchorTranslation.x, y: t.y - collapsePanAnchorTranslation.y)
        let velocityInView = gr.velocity(in: view)

        switch gr.state {
        case .began:
            collapsePanAxis = .undecided
            collapsePanAnchorTranslation = t
            collapsePanAnchorDelta = inputBarCollapseDelta
            collapseTranslationAtHorizontalLock = nil
            collapsePanBeganInCollapsedMenu = inputBar.isCollapsed
                && inputBar.menuButton.frame.contains(gr.location(in: inputBar))

        case .changed:
            let ax = abs(tFromAnchor.x)
            let ay = abs(tFromAnchor.y)

            if collapsePanAxis == .undecided {
                if max(ax, ay) < Self.inputBarCollapseAxisLockThreshold { return }
                if inputBar.textField.isFirstResponder, ay > ax * 1.35 { return }
                if collapsePanBeganInCollapsedMenu, ax >= ay {
                    collapsePanAxis = .menuExpand
                    menuExpandAnchorDelta = inputBarCollapseDelta
                    menuExpandAnchorTranslation = t
                } else if isHorizontalCollapsePan(translationFromBegan: tFromAnchor, velocityInView: velocityInView) {
                    collapsePanAxis = .horizontal
                    collapseTranslationAtHorizontalLock = t
                    collapsePanAnchorDelta = inputBarCollapseDelta
                }
            }

            switch collapsePanAxis {
            case .undecided:
                if isHorizontalCollapsePan(translationFromBegan: tFromAnchor, velocityInView: velocityInView) {
                    applyProvisionalHorizontalCollapseDelta(translationFromBegan: tFromAnchor)
                }
            case .menuExpand:
                let cap = inputBarMaxCollapseDelta
                guard cap > 0 else { break }
                let dx = t.x - menuExpandAnchorTranslation.x
                inputBarCollapseDelta = Self.clamp(menuExpandAnchorDelta + dx, 0, cap)
                layoutInputBar()
                inputBar.setNeedsLayout()
            case .horizontal:
                syncHorizontalCollapseDeltaFromPan(gr)
            }

        case .ended, .cancelled, .failed:
            let vx = velocityInView.x
            let shouldFinish: Bool
            switch collapsePanAxis {
            case .horizontal, .menuExpand:
                shouldFinish = true
            case .undecided:
                shouldFinish = isHorizontalCollapsePan(translationFromBegan: tFromAnchor, velocityInView: velocityInView)
            }
            if shouldFinish {
                syncHorizontalCollapseDeltaFromPan(gr, useFullTranslationFromBegan: true)
                handleInputBarCollapsePanEnded(velocityX: vx)
            }
            collapsePanAxis = .undecided
            collapsePanAnchorTranslation = .zero
            collapseTranslationAtHorizontalLock = nil
            collapsePanBeganInCollapsedMenu = false

        default:
            break
        }
    }

    /// 松手吸附：用「惯性投影位置 + 中线」决定最终展开还是收起。
    ///
    /// 核心思路（与系统 sheet / 抽屉一致）：不要只看手指松开瞬间停在哪，
    /// 而要预测「如果带着这个速度继续滑，最终会停在哪」，再用这个预测位置去比中线。
    /// 这样「滑到一半但还在快速往收起方向甩」也会正确地完成收起。
    ///
    /// - Parameters:
    ///   - currentDelta: 松手瞬间的收起量（0 = 完全展开，cap = 完全收起）。
    ///   - velocityX: 松手瞬间横向速度（pt/s，正 = 向右 = 收起方向）。
    ///   - cap: 最大收起量（= 展开宽 − 收起宽）。
    /// - Returns: 吸附目标 delta，只会是 0 或 cap。
    private func resolveInputBarCollapseTarget(currentDelta: CGFloat, velocityX vx: CGFloat, cap: CGFloat) -> CGFloat {
        // 1) 强甩动优先：速度过阈值直接按方向定输赢，不再看位置（最跟手）。
        //    向右收起阈值低于向左展开阈值 → 轻轻一甩即可收起，符合「收起是常用动作」的预期。
        if vx > Self.inputBarCollapseFastVelocityRight { return cap }   // 向右快甩 → 收起
        if vx < -Self.inputBarCollapseFastVelocityLeft { return 0 }     // 向左快甩 → 展开

        // 2) 惯性投影：估算手指松开后凭惯性还会滑动的距离，叠加到当前位置 → 预测落点。
        let projectedDelta = currentDelta + vx * Self.inputBarCollapseProjectionFactor

        // 3) 中线吸附：预测落点过半收起，否则展开。clamp 仅为稳健。
        let clampedProjected = Self.clamp(projectedDelta, 0, cap)
        return clampedProjected >= cap * 0.5 ? cap : 0
    }

    private func handleInputBarCollapsePanEnded(velocityX vx: CGFloat) {
        let cap = inputBarMaxCollapseDelta
        guard cap > 0 else { return }
        let target = resolveInputBarCollapseTarget(currentDelta: inputBarCollapseDelta, velocityX: vx, cap: cap)

        // 已在目标位置（差 < 0.5pt）则无需动画。
        guard abs(inputBarCollapseDelta - target) > 0.5 else { return }

        // 弹簧初速度继承手指松开瞬间的速度，动画才不会「顿一下再走」。
        // initialSpringVelocity 单位是「每秒走完剩余距离的倍数」，故用 pt/s 除以剩余位移归一化。
        let remaining = abs(target - inputBarCollapseDelta)
        let initialSpringVelocity = remaining > 0 ? abs(vx) / remaining : 0

        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.82,        // < 1 留一点回弹，手感更软；越接近 1 越生硬
            initialSpringVelocity: initialSpringVelocity,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.inputBarCollapseDelta = target
                self.layoutInputBar()
                self.inputBar.setNeedsLayout()
                self.inputBar.layoutIfNeeded()
            }
        )
    }
}

// MARK: - UITableViewDataSource

extension OpenAPPViewController: UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chatMessages.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatMessageCell.reuseIdentifier, for: indexPath) as! ChatMessageCell
        cell.configure(with: chatMessages[indexPath.row])
        return cell
    }
}

// MARK: - OpenAPPInputBarDelegate

extension OpenAPPViewController: OpenAPPInputBarDelegate {
    public func inputBar(_ bar: OpenAPPInputBar, didSendText text: String) {
        sendMessage(text: text)
    }

    public func inputBarDidRequestExpand(_ bar: OpenAPPInputBar) {
        setInputBarCollapsed(false, animated: true)
    }

    public func inputBarDidTapMenu(_ bar: OpenAPPInputBar) {
        // Override in subclass or set up delegate chain
    }

    public func inputBarDidTapVoice(_ bar: OpenAPPInputBar) {
        // Override in subclass or set up delegate chain
    }

    public func inputBarDidTapPlus(_ bar: OpenAPPInputBar) {
        // Override in subclass or set up delegate chain
    }
}

// MARK: - UIGestureRecognizerDelegate

extension OpenAPPViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === inputBarCollapsePan || otherGestureRecognizer === inputBarCollapsePan {
            return true
        }
        return false
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

#endif
