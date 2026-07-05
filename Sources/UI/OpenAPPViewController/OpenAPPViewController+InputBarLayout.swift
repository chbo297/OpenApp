//
//  OpenAPPViewController+InputBarLayout.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

// MARK: - Input Bar Layout

extension OpenAPPViewController {
    func layoutInputBar(reason: OpenAPPInputBarFrameChangeReason) {
        guard inputBarContainerAvailableFrame.width > 0, inputBarContainerAvailableFrame.height > 0 else {
            layoutTableView()
            return
        }

        let targetFrame: CGRect
        if !hasLaidOutInputBar {
            targetFrame = preferredExpandedInputBarFrame()
            hasLaidOutInputBar = true
        } else if isDraggingExpandedInputBar {
            targetFrame = constrainedExpandedInputBarFrame(inputBar.frame)
        } else if isDraggingCollapsedInputBar {
            targetFrame = constrainedCollapsedInputBarFrame(inputBar.frame)
        } else if inputBar.isCollapsed {
            targetFrame = preferredCollapsedInputBarFrame()
        } else {
            targetFrame = preferredExpandedInputBarFrame()
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
        abs(oldFrame.minX - newFrame.minX) > 0.5
            || abs(oldFrame.minY - newFrame.minY) > 0.5
            || abs(oldFrame.width - newFrame.width) > 0.5
            || abs(oldFrame.height - newFrame.height) > 0.5
    }

    func expandInputBar(animated: Bool) {
        isDraggingExpandedInputBar = false
        isDraggingCollapsedInputBar = false
        resetExpandedResizeWidthHoldTracking()
        applyInputBarFrame(preferredExpandedInputBarFrame(), animated: animated, reason: .expand)
    }

    func collapseInputBar(animated: Bool) {
        isDraggingExpandedInputBar = false
        isDraggingCollapsedInputBar = false
        resetExpandedResizeWidthHoldTracking()
        applyInputBarFrame(preferredCollapsedInputBarFrame(), animated: animated, reason: .collapse)
    }

    var inputBarAvailableFrame: CGRect {
        makeInputBarAvailableFrame(avoidingKeyboard: true)
    }

    var inputBarContainerAvailableFrame: CGRect {
        makeInputBarAvailableFrame(avoidingKeyboard: false)
    }

    func makeInputBarAvailableFrame(avoidingKeyboard: Bool) -> CGRect {
        let bounds = view.bounds
        let safeInsets = view.safeAreaInsets
        let safeTop = safeInsets.top
        let keyboardHeight = effectiveKeyboardHeight
        let bottom = avoidingKeyboard && keyboardHeight > 0
            ? bounds.height - keyboardHeight - Self.inputBarKeyboardSpacing
            : bounds.height - safeInsets.bottom
        let x = safeInsets.left + Self.inputBarHorizontalInset
        let maxX = max(x, bounds.width - safeInsets.right - Self.inputBarHorizontalInset)
        return CGRect(
            x: x,
            y: safeTop,
            width: max(0, maxX - x),
            height: max(0, bottom - safeTop)
        )
    }

    func isWideInputBarLayout() -> Bool {
        view.bounds.width > Self.inputBarWideLayoutWidth
    }

    func defaultExpandedInputBarWidth() -> CGFloat {
        let available = inputBarAvailableFrame
        guard isWideInputBarLayout() else {
            return available.width
        }

        return min(Self.inputBarWideDefaultMaxWidth, available.width)
    }

    func preferredExpandedInputBarWidth() -> CGFloat {
        let available = inputBarAvailableFrame
        guard isWideInputBarLayout() else {
            return available.width
        }

        guard let storedWidth = storedExpandedInputBarWidth,
              storedWidth >= OpenAPPInputBar.minimumExpandedWidth else {
            return defaultExpandedInputBarWidth()
        }

        return clampedExpandedInputBarWidth(storedWidth)
    }

    func preferredExpandedInputBarFrame() -> CGRect {
        expandedInputBarFrame(width: preferredExpandedInputBarWidth())
    }

    func expandedInputBarFrame(width: CGFloat) -> CGRect {
        let available = inputBarAvailableFrame
        let clampedWidth = clampedExpandedInputBarWidth(width)
        let x = available.midX - clampedWidth / 2
        return CGRect(
            x: x,
            y: max(available.minY, available.maxY - OpenAPPInputBar.barHeight),
            width: clampedWidth,
            height: OpenAPPInputBar.barHeight
        )
    }

    func defaultCollapsedInputBarFrame() -> CGRect {
        let available = inputBarContainerAvailableFrame
        let width = OpenAPPInputBar.collapsedMinWidth
        return CGRect(
            x: max(available.minX, available.maxX - width),
            y: max(available.minY, available.maxY - OpenAPPInputBar.barHeight),
            width: width,
            height: OpenAPPInputBar.barHeight
        )
    }

    func preferredCollapsedInputBarFrame() -> CGRect {
        guard let placement = storedCollapsedInputBarPlacement else {
            return defaultCollapsedInputBarFrame()
        }
        return constrainedCollapsedInputBarFrame(collapsedInputBarFrame(fromStoredPlacement: placement))
    }

    func collapsedInputBarFrame(fromStoredPlacement placement: CGPoint) -> CGRect {
        let available = inputBarContainerAvailableFrame
        let width = OpenAPPInputBar.collapsedMinWidth
        let height = OpenAPPInputBar.barHeight
        let x = placement.x.sign == .minus
            ? available.maxX - width + placement.x
            : available.minX + placement.x
        let y = placement.y.sign == .minus
            ? available.maxY - height + placement.y
            : available.minY + placement.y
        return CGRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }

    func clampedExpandedInputBarWidth(_ width: CGFloat) -> CGFloat {
        let availableWidth = inputBarAvailableFrame.width
        guard availableWidth > 0 else { return 0 }
        let minWidth = min(OpenAPPInputBar.minimumExpandedWidth, availableWidth)
        return Self.clamp(width, minWidth, availableWidth)
    }

    func constrainedExpandedInputBarFrame(_ proposedFrame: CGRect) -> CGRect {
        let available = inputBarAvailableFrame
        let width = Self.clamp(
            proposedFrame.width,
            OpenAPPInputBar.collapsedMinWidth,
            max(OpenAPPInputBar.collapsedMinWidth, available.width)
        )
        let minX = available.minX
        let maxX = max(available.minX, available.maxX - width)
        let x = Self.clamp(proposedFrame.maxX - width, minX, maxX)
        let y = max(available.minY, available.maxY - OpenAPPInputBar.barHeight)
        return CGRect(x: x, y: y, width: width, height: OpenAPPInputBar.barHeight)
    }

    func constrainedCollapsedInputBarFrame(_ proposedFrame: CGRect) -> CGRect {
        let available = inputBarContainerAvailableFrame
        let width = OpenAPPInputBar.collapsedMinWidth
        let height = OpenAPPInputBar.barHeight
        let maxX = max(available.minX, available.maxX - width)
        let maxY = max(available.minY, available.maxY - height)
        return CGRect(
            x: Self.clamp(proposedFrame.minX, available.minX, maxX),
            y: Self.clamp(proposedFrame.minY, available.minY, maxY),
            width: width,
            height: height
        )
    }

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

    func storableExpandedInputBarWidth(_ width: CGFloat) -> CGFloat? {
        let availableWidth = inputBarAvailableFrame.width
        guard isWideInputBarLayout(),
              availableWidth >= OpenAPPInputBar.minimumExpandedWidth,
              width >= OpenAPPInputBar.minimumExpandedWidth else {
            return nil
        }
        return Self.clamp(width, OpenAPPInputBar.minimumExpandedWidth, availableWidth)
    }

    func resetExpandedResizeWidthHoldTracking() {
        expandedResizeStableWidth = nil
        expandedResizeStableStartTime = nil
    }

    func loadPersistedInputBarLayout() {
        storedExpandedInputBarWidth = loadPersistedExpandedInputBarWidth()
        storedCollapsedInputBarPlacement = loadPersistedCollapsedInputBarPlacement()
    }

    func loadPersistedExpandedInputBarWidth() -> CGFloat? {
        guard UserDefaults.standard.object(forKey: Self.expandedWidthDefaultsKey) != nil else {
            return nil
        }

        let width = CGFloat(UserDefaults.standard.double(forKey: Self.expandedWidthDefaultsKey))
        guard width.isFinite, width >= OpenAPPInputBar.minimumExpandedWidth else {
            return nil
        }
        return width
    }

    func persistExpandedInputBarWidth(_ width: CGFloat) {
        guard let storedWidth = storableExpandedInputBarWidth(width) else { return }
        storedExpandedInputBarWidth = storedWidth
        UserDefaults.standard.set(Double(storedWidth), forKey: Self.expandedWidthDefaultsKey)
    }

    func loadPersistedCollapsedInputBarPlacement() -> CGPoint? {
        guard let value = UserDefaults.standard.string(forKey: Self.collapsedPlacementDefaultsKey) else {
            return nil
        }
        return Self.parseCollapsedInputBarPlacement(value)
    }

    func persistCollapsedInputBarPlacement(for frame: CGRect) {
        let constrainedFrame = constrainedCollapsedInputBarFrame(frame)
        let placement = collapsedInputBarPlacement(for: constrainedFrame)
        storedCollapsedInputBarPlacement = placement
        UserDefaults.standard.set(
            Self.encodeCollapsedInputBarPlacement(placement),
            forKey: Self.collapsedPlacementDefaultsKey
        )
    }

    func collapsedInputBarPlacement(for frame: CGRect) -> CGPoint {
        let available = inputBarContainerAvailableFrame
        let leftOffset = frame.minX - available.minX
        let rightOffset = Self.trailingPlacementOffset(frame.minX - (available.maxX - frame.width))
        let topOffset = frame.minY - available.minY
        let bottomOffset = Self.trailingPlacementOffset(frame.minY - (available.maxY - frame.height))
        let x = leftOffset <= abs(rightOffset) ? leftOffset : rightOffset
        let y = topOffset <= abs(bottomOffset) ? topOffset : bottomOffset
        return CGPoint(x: x, y: y)
    }

    static func trailingPlacementOffset(_ offset: CGFloat) -> CGFloat {
        offset == 0 ? CGFloat(-0.0) : offset
    }

    static func parseCollapsedInputBarPlacement(_ value: String) -> CGPoint? {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let x = Double(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
              let y = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
              x.isFinite,
              y.isFinite else {
            return nil
        }
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }

    static func encodeCollapsedInputBarPlacement(_ placement: CGPoint) -> String {
        "\(Double(placement.x)),\(Double(placement.y))"
    }

    static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(hi, max(lo, v))
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
