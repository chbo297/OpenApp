//
//  OpenAPPViewController+InputBarFrameResolution.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

// MARK: - Input Bar Frame Resolution

extension OpenAPPViewController {
    func finishExpandedInputBarResize(velocity: CGPoint, frame: CGRect) {
        let currentFrame = constrainedExpandedInputBarFrame(frame)
        let speed = abs(velocity.x)

        if currentFrame.width < OpenAPPInputBar.minimumExpandedWidth {
            collapseInputBar(animated: true)
            return
        }

        if speed <= Self.inputBarSlowVelocityThreshold,
           didHoldExpandedResizeWidth(width: currentFrame.width),
           let storedWidth = storableExpandedInputBarWidth(currentFrame.width) {
            persistExpandedInputBarWidth(storedWidth)
            expandInputBar(animated: true)
            return
        }

        if shouldCollapseExpandedInputBar(velocityX: velocity.x, frame: currentFrame) {
            collapseInputBar(animated: true)
        } else {
            expandInputBar(animated: true)
        }
    }

    func finishCollapsedInputBarMove(_ context: OpenAPPInputBarFramePanEndContext) {
        let currentFrame = constrainedCollapsedInputBarFrame(context.frame)
        let targetFrame = context.didHoldNearFinalPosition
            ? currentFrame
            : resolvedCollapsedInputBarSnapFrame(velocity: context.velocity, frame: currentFrame)
        persistCollapsedInputBarPlacement(for: targetFrame)
        isDraggingExpandedInputBar = false
        isDraggingCollapsedInputBar = false
        applyInputBarFrame(
            targetFrame,
            animated: !context.didHoldNearFinalPosition,
            reason: .collapsedMoveResolution
        )
    }

    func shouldCollapseExpandedInputBar(velocityX vx: CGFloat, frame: CGRect) -> Bool {
        let minWidth = OpenAPPInputBar.collapsedMinWidth
        let maxWidth = preferredExpandedInputBarWidth()
        let speed = abs(vx)

        guard frame.width >= OpenAPPInputBar.minimumExpandedWidth else {
            return true
        }

        if speed >= Self.inputBarFastVelocityThreshold {
            return vx > 0
        }

        let decisionWidth: CGFloat
        if speed <= Self.inputBarSlowVelocityThreshold {
            decisionWidth = frame.width
        } else {
            decisionWidth = Self.clamp(
                frame.width - vx * Self.inputBarProjectionFactor,
                minWidth,
                maxWidth
            )
        }
        if decisionWidth < OpenAPPInputBar.minimumExpandedWidth {
            return true
        }
        return decisionWidth < (minWidth + maxWidth) * 0.5
    }

    func resolvedCollapsedInputBarSnapFrame(velocity: CGPoint, frame: CGRect) -> CGRect {
        let available = inputBarContainerAvailableFrame
        let leftFrame = CGRect(
            x: available.minX,
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
        let rightFrame = CGRect(
            x: available.maxX - frame.width,
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
        let bottomFrame = CGRect(
            x: frame.minX,
            y: available.maxY - frame.height,
            width: frame.width,
            height: frame.height
        )

        let velocityX = abs(velocity.x)
        let velocityY = abs(velocity.y)
        let allowsBottomSnap = isWideInputBarLayout()

        if allowsBottomSnap,
           velocity.y >= Self.inputBarFastVelocityThreshold,
           velocityY >= velocityX {
            return constrainedCollapsedInputBarFrame(bottomFrame)
        }

        if velocityX >= Self.inputBarFastVelocityThreshold {
            return constrainedCollapsedInputBarFrame(velocity.x < 0 ? leftFrame : rightFrame)
        }

        guard allowsBottomSnap else {
            let projectedCenterX = frame.midX + velocity.x * Self.inputBarProjectionFactor
            let shouldSnapLeft = abs(projectedCenterX - leftFrame.midX) <= abs(projectedCenterX - rightFrame.midX)
            return constrainedCollapsedInputBarFrame(shouldSnapLeft ? leftFrame : rightFrame)
        }

        let projectedCenter = CGPoint(
            x: frame.midX + velocity.x * Self.inputBarProjectionFactor,
            y: frame.midY + velocity.y * Self.inputBarProjectionFactor
        )
        func distanceSquared(to candidate: CGRect) -> CGFloat {
            let dx = projectedCenter.x - candidate.midX
            let dy = projectedCenter.y - candidate.midY
            return dx * dx + dy * dy
        }

        let targetFrame = [leftFrame, rightFrame, bottomFrame].min {
            distanceSquared(to: $0) < distanceSquared(to: $1)
        } ?? rightFrame
        return constrainedCollapsedInputBarFrame(targetFrame)
    }
}

#endif
