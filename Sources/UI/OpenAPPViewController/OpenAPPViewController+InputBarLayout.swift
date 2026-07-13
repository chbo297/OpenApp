//
//  OpenAPPViewController+InputBarLayout.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

// MARK: - Input Bar Layout（接线层）
//
// frame 的纯计算与落位策略在 OpenAPPInputBarFramePolicy，持久化在 OpenAPPInputBarLayoutStoring；
// 这里只保留状态（拖拽标志、宽度停留计时、已存偏好）与视图应用。

extension OpenAPPViewController {

    /// 当前布局决策的环境快照。
    var inputBarLayoutContext: OpenAPPInputBarFramePolicy.Context {
        OpenAPPInputBarFramePolicy.Context(
            bounds: view.bounds,
            safeAreaInsets: view.safeAreaInsets,
            keyboardHeight: effectiveKeyboardHeight,
            storedExpandedWidth: storedExpandedInputBarWidth,
            storedCollapsedPlacement: storedCollapsedInputBarPlacement
        )
    }

    var inputBarAvailableFrame: CGRect {
        OpenAPPInputBarFramePolicy.availableFrame(in: inputBarLayoutContext, avoidingKeyboard: true)
    }

    var inputBarContainerAvailableFrame: CGRect {
        OpenAPPInputBarFramePolicy.availableFrame(in: inputBarLayoutContext, avoidingKeyboard: false)
    }

    func isWideInputBarLayout() -> Bool {
        OpenAPPInputBarFramePolicy.isWideLayout(inputBarLayoutContext)
    }

    // MARK: 布局分发

    func layoutInputBar(reason: OpenAPPInputBarFrameChangeReason) {
        guard inputBarContainerAvailableFrame.width > 0, inputBarContainerAvailableFrame.height > 0 else {
            layoutTableView()
            return
        }

        let context = inputBarLayoutContext
        let targetFrame: CGRect
        if !hasLaidOutInputBar {
            targetFrame = OpenAPPInputBarFramePolicy.preferredExpandedFrame(context)
            hasLaidOutInputBar = true
        } else if isDraggingExpandedInputBar {
            targetFrame = OpenAPPInputBarFramePolicy.constrainedExpandedFrame(inputBar.frame, context: context)
        } else if isDraggingCollapsedInputBar {
            targetFrame = OpenAPPInputBarFramePolicy.constrainedCollapsedFrame(inputBar.frame, context: context)
        } else if inputBar.isCollapsed {
            targetFrame = OpenAPPInputBarFramePolicy.preferredCollapsedFrame(context)
        } else {
            targetFrame = OpenAPPInputBarFramePolicy.preferredExpandedFrame(context)
        }
        applyInputBarFrame(targetFrame, animated: false, reason: reason)
    }

    func layoutTableView() {
        let bounds = view.bounds
        let safeTop = view.safeAreaInsets.top
        let tableY = safeTop
        let tableBottom = max(tableY, inputBarAvailableFrame.maxY - OpenAPPInputBar.barHeight)
        let tableH = max(0, tableBottom - tableY)
        tableView.frame = CGRect(x: 0, y: tableY, width: bounds.width, height: tableH)
    }

    func applyInputBarFrame(
        _ targetFrame: CGRect,
        animated: Bool,
        reason: OpenAPPInputBarFrameChangeReason
    ) {
        let oldFrame = inputBar.frame
        guard didInputBarFrameChange(from: oldFrame, to: targetFrame) else {
            if reason.needsTableViewRelayout {
                layoutTableView()
            }
            return
        }

        inputBar.setInputBarFrame(targetFrame, animated: animated)
        if reason.needsTableViewRelayout {
            layoutTableView()
        }
        notifyInputBarFrameChangeIfNeeded(
            oldFrame: oldFrame,
            newFrame: inputBar.frame,
            animated: animated,
            reason: reason
        )
    }

    func notifyInputBarFrameChangeIfNeeded(
        oldFrame: CGRect,
        newFrame: CGRect,
        animated: Bool,
        reason: OpenAPPInputBarFrameChangeReason
    ) {
        guard didInputBarFrameChange(from: oldFrame, to: newFrame) else { return }
        let context = OpenAPPInputBarFrameChangeContext(
            reason: reason,
            oldFrame: oldFrame,
            newFrame: newFrame,
            animated: animated
        )
        onInputBarFrameChange?(context)
        inputBarFrameDidChange(context)
    }

    func didInputBarFrameChange(from oldFrame: CGRect, to newFrame: CGRect) -> Bool {
        !oldFrame.isApproximatelyEqual(to: newFrame)
    }

    func expandInputBar(animated: Bool) {
        isDraggingExpandedInputBar = false
        isDraggingCollapsedInputBar = false
        resetExpandedResizeWidthHoldTracking()
        applyInputBarFrame(
            OpenAPPInputBarFramePolicy.preferredExpandedFrame(inputBarLayoutContext),
            animated: animated,
            reason: .expand
        )
    }

    func collapseInputBar(animated: Bool) {
        isDraggingExpandedInputBar = false
        isDraggingCollapsedInputBar = false
        resetExpandedResizeWidthHoldTracking()
        applyInputBarFrame(
            OpenAPPInputBarFramePolicy.preferredCollapsedFrame(inputBarLayoutContext),
            animated: animated,
            reason: .collapse
        )
    }

    // MARK: 拖拽约束（inputBar delegate 拖拽期间调用）

    func constrainedExpandedInputBarFrame(_ proposedFrame: CGRect) -> CGRect {
        OpenAPPInputBarFramePolicy.constrainedExpandedFrame(proposedFrame, context: inputBarLayoutContext)
    }

    func constrainedCollapsedInputBarFrame(_ proposedFrame: CGRect) -> CGRect {
        OpenAPPInputBarFramePolicy.constrainedCollapsedFrame(proposedFrame, context: inputBarLayoutContext)
    }

    // MARK: 松手结算

    func finishExpandedInputBarResize(velocity: CGPoint, frame: CGRect) {
        let context = inputBarLayoutContext
        let currentFrame = OpenAPPInputBarFramePolicy.constrainedExpandedFrame(frame, context: context)
        let speed = abs(velocity.x)

        if currentFrame.width < OpenAPPInputBar.minimumExpandedWidth {
            collapseInputBar(animated: true)
            return
        }

        if speed <= OpenAPPInputBarFramePolicy.slowVelocityThreshold,
           didHoldExpandedResizeWidth(width: currentFrame.width),
           let storedWidth = OpenAPPInputBarFramePolicy.storableExpandedWidth(currentFrame.width, context: context) {
            persistExpandedInputBarWidth(storedWidth)
            expandInputBar(animated: true)
            return
        }

        if OpenAPPInputBarFramePolicy.shouldCollapseExpanded(velocityX: velocity.x, frame: currentFrame, context: context) {
            collapseInputBar(animated: true)
        } else {
            expandInputBar(animated: true)
        }
    }

    func finishCollapsedInputBarMove(_ context: OpenAPPInputBarFramePanEndContext) {
        let layoutContext = inputBarLayoutContext
        let currentFrame = OpenAPPInputBarFramePolicy.constrainedCollapsedFrame(context.frame, context: layoutContext)
        let targetFrame = context.didHoldNearFinalPosition
            ? currentFrame
            : OpenAPPInputBarFramePolicy.collapsedSnapFrame(
                velocity: context.velocity,
                frame: currentFrame,
                context: layoutContext
            )
        persistCollapsedInputBarPlacement(for: targetFrame)
        isDraggingExpandedInputBar = false
        isDraggingCollapsedInputBar = false
        applyInputBarFrame(
            targetFrame,
            animated: !context.didHoldNearFinalPosition,
            reason: .collapsedMoveResolution
        )
    }

    // MARK: 展开宽度停留跟踪（时间状态在 VC）

    func updateExpandedResizeWidthHoldTracking(width: CGFloat) {
        guard isWideInputBarLayout(),
              width >= OpenAPPInputBar.minimumExpandedWidth else {
            resetExpandedResizeWidthHoldTracking()
            return
        }

        guard let stableWidth = expandedResizeStableWidth,
              abs(width - stableWidth) <= Self.expandedResizeWidthStabilityThreshold else {
            expandedResizeStableWidth = width
            expandedResizeStableStartTime = Date.timeIntervalSinceReferenceDate
            return
        }
    }

    func didHoldExpandedResizeWidth(width: CGFloat) -> Bool {
        guard isWideInputBarLayout(),
              width >= OpenAPPInputBar.minimumExpandedWidth,
              let stableWidth = expandedResizeStableWidth,
              let startTime = expandedResizeStableStartTime,
              abs(width - stableWidth) <= Self.expandedResizeWidthStabilityThreshold else {
            return false
        }

        return Date.timeIntervalSinceReferenceDate - startTime >= Self.expandedResizeHoldDuration
    }

    func resetExpandedResizeWidthHoldTracking() {
        expandedResizeStableWidth = nil
        expandedResizeStableStartTime = nil
    }

    // MARK: 持久化

    func loadPersistedInputBarLayout() {
        storedExpandedInputBarWidth = inputBarLayoutStore.loadExpandedWidth()
        storedCollapsedInputBarPlacement = inputBarLayoutStore.loadCollapsedPlacement()
    }

    func persistExpandedInputBarWidth(_ width: CGFloat) {
        guard let storedWidth = OpenAPPInputBarFramePolicy.storableExpandedWidth(width, context: inputBarLayoutContext) else {
            return
        }
        storedExpandedInputBarWidth = storedWidth
        inputBarLayoutStore.saveExpandedWidth(storedWidth)
    }

    func persistCollapsedInputBarPlacement(for frame: CGRect) {
        let context = inputBarLayoutContext
        let constrainedFrame = OpenAPPInputBarFramePolicy.constrainedCollapsedFrame(frame, context: context)
        let placement = OpenAPPInputBarFramePolicy.collapsedPlacement(for: constrainedFrame, context: context)
        storedCollapsedInputBarPlacement = placement
        inputBarLayoutStore.saveCollapsedPlacement(placement)
    }
}

private extension OpenAPPInputBarFrameChangeReason {
    var needsTableViewRelayout: Bool {
        switch self {
        case .layout, .keyboard:
            return true
        case .expand, .collapse, .expandedResizePan, .collapsedMovePan, .collapsedMoveResolution:
            return false
        }
    }
}

#endif
