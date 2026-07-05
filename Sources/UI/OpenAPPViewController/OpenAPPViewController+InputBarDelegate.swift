//
//  OpenAPPViewController+InputBarDelegate.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

// MARK: - OpenAPPInputBarDelegate

extension OpenAPPViewController: OpenAPPInputBarDelegate {
    func setupInputBar() {
        inputBar.delegate = self
        inputBar.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(inputBar)
    }

    // 场景：文字输入态点击发送或键盘提交文本时触发。
    public func inputBar(_ bar: OpenAPPInputBar, didSendText text: String) {
        logInputBarDelegate("didSendText textLength=\(text.count)")
        sendMessage(text: text)
    }

    // 场景：inputBar 内部切换键盘/语音输入源后触发。
    public func inputBar(_ bar: OpenAPPInputBar, didChangeInputSource source: OpenAPPInputBarInputSource) {
        logInputBarDelegate("didChangeInputSource source=\(source)")
    }

    // 场景：inputBar 的 textField 激活或失焦时触发，用当前已观察到的键盘高度重新计算 inputBar 是否需要避让。
    public func inputBar(_ bar: OpenAPPInputBar, didChangeTextInputFocus isFocused: Bool) {
        logInputBarDelegate("didChangeTextInputFocus isFocused=\(isFocused)")
        layoutInputBar(reason: .keyboard)
        if isFocused {
            scrollToBottom(animated: true)
        }
    }

    // 场景：收起态点击 menu 按钮，或手势结算后判定需要展开输入栏时触发。
    public func inputBarDidRequestExpand(_ bar: OpenAPPInputBar) {
        logInputBarDelegate("inputBarDidRequestExpand")
        expandInputBar(animated: true)
    }

    // 场景：展开态点击 menu 按钮，或手势结算后判定需要收起输入栏时触发。
    public func inputBarDidRequestCollapse(_ bar: OpenAPPInputBar) {
        logInputBarDelegate("inputBarDidRequestCollapse")
        collapseInputBar(animated: true)
    }

    // 场景：拖拽 menu 按钮过程中，inputBar 持续提出 frame 变化意图时触发。
    public func inputBar(
        _ bar: OpenAPPInputBar,
        wantsFrame frame: CGRect,
        panKind kind: OpenAPPInputBarFramePanKind
    ) {
        logInputBarDelegate("wantsFrame kind=\(kind) frame=\(formatInputBarDelegateRect(frame))")
        let constrainedFrame: CGRect
        switch kind {
        case .expandedResize:
            isDraggingExpandedInputBar = true
            isDraggingCollapsedInputBar = false
            constrainedFrame = constrainedExpandedInputBarFrame(frame)
            updateExpandedResizeWidthHoldTracking(width: constrainedFrame.width)
        case .collapsedMove:
            isDraggingExpandedInputBar = false
            isDraggingCollapsedInputBar = true
            constrainedFrame = constrainedCollapsedInputBarFrame(frame)
            resetExpandedResizeWidthHoldTracking()
        }
        let reason: OpenAPPInputBarFrameChangeReason = kind == .expandedResize
            ? .expandedResizePan
            : .collapsedMovePan
        applyInputBarFrame(constrainedFrame, animated: false, reason: reason)
    }

    // 场景：menu 按钮拖拽改变 inputBar frame 的手势结束时触发；展开 resize 和收起 move 在这里统一分发。
    public func inputBar(
        _ bar: OpenAPPInputBar,
        didEndFramePan context: OpenAPPInputBarFramePanEndContext
    ) {
        logInputBarDelegate(
            "didEndFramePan kind=\(context.kind) velocity=\(formatInputBarDelegatePoint(context.velocity)) frame=\(formatInputBarDelegateRect(context.frame)) didHoldNearFinalPosition=\(context.didHoldNearFinalPosition)"
        )
        switch context.kind {
        case .expandedResize:
            finishExpandedInputBarResize(velocity: context.velocity, frame: context.frame)
        case .collapsedMove:
            finishCollapsedInputBarMove(context)
        }
    }

    // 场景：文字输入态长按输入区域，或语音输入态按住“按住说话”区域时触发；begin/change/end/cancel 都通过这个方法透传。
    public func inputBar(
        _ bar: OpenAPPInputBar,
        didReceiveVoiceInputGesture gestureRecognizer: UILongPressGestureRecognizer,
        source: OpenAPPInputBarVoiceInputSource,
        state: UIGestureRecognizer.State
    ) {
        logInputBarDelegate(
            "didReceiveVoiceInputGesture source=\(source) state=\(inputBarDelegateGestureStateName(state)) location=\(formatInputBarDelegatePoint(gestureRecognizer.location(in: view)))"
        )
        handleVoiceInputGesture(gestureRecognizer, source: source, state: state)
    }

    // 场景：点击输入源切换按钮中的语音图标时触发，默认由 inputBar 内部完成键盘/语音模式切换。
    public func inputBarDidTapVoice(_ bar: OpenAPPInputBar) {
        logInputBarDelegate("inputBarDidTapVoice")
        // Override in subclass or set up delegate chain
    }

    // 场景：点击加号按钮时触发，用于宿主接入附件、工具或更多能力入口。
    public func inputBarDidTapPlus(_ bar: OpenAPPInputBar) {
        logInputBarDelegate("inputBarDidTapPlus")
        // Override in subclass or set up delegate chain
    }

    func logInputBarDelegate(_ message: @autoclosure () -> String) {
        guard Self.isInputBarDelegateDebugLoggingEnabled else { return }
        print("[OpenAPPInputBarDelegate] \(message())")
    }

    func formatInputBarDelegatePoint(_ point: CGPoint) -> String {
        String(format: "(%.1f, %.1f)", point.x, point.y)
    }

    func formatInputBarDelegateRect(_ rect: CGRect) -> String {
        String(
            format: "(x: %.1f, y: %.1f, w: %.1f, h: %.1f)",
            rect.origin.x,
            rect.origin.y,
            rect.size.width,
            rect.size.height
        )
    }

    func inputBarDelegateGestureStateName(_ state: UIGestureRecognizer.State) -> String {
        switch state {
        case .possible:
            return "possible"
        case .began:
            return "began"
        case .changed:
            return "changed"
        case .ended:
            return "ended"
        case .cancelled:
            return "cancelled"
        case .failed:
            return "failed"
        @unknown default:
            return "unknown"
        }
    }
}

#endif
