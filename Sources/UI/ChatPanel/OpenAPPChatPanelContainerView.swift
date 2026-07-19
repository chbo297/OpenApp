//
//  OpenAPPChatPanelContainerView.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

/// ChatPanel 裁剪容器的纯布局结果。
///
/// `dragScrollView` 保持原始尺寸并跟随 container 横向移动；container 和 mask 只控制可见窗口，
/// 避免 inputBar 收起动画污染 BODragScroll 的滚动几何。
struct OpenAPPChatPanelContainerLayout: Equatable {
    let containerFrame: CGRect
    let dragScrollFrame: CGRect
    let maskFrame: CGRect
    let maskCornerRadius: CGFloat
    let hidesAccessibilityElements: Bool

    init(
        bounds: CGRect,
        inputBarFrame: CGRect,
        inputBarExpandedFrame: CGRect,
        inputBarCornerRadius: CGFloat
    ) {
        guard bounds.width > 0,
              bounds.height > 0,
              inputBarFrame.width > 0,
              inputBarFrame.height > 0 else {
            containerFrame = .zero
            dragScrollFrame = .zero
            maskFrame = .zero
            maskCornerRadius = 0
            hidesAccessibilityElements = true
            return
        }

        let collapseProgress = Self.collapseProgress(
            inputBarWidth: inputBarFrame.width,
            expandedInputBarWidth: inputBarExpandedFrame.width
        )
        let expandedContainerFrame = Self.expandedContainerFrame(
            bounds: bounds,
            inputBarExpandedFrame: inputBarExpandedFrame
        )
        let collapsedContainerFrame = CGRect(
            x: inputBarFrame.minX,
            y: bounds.minY,
            width: inputBarFrame.width,
            height: bounds.height
        )

        containerFrame = Self.interpolate(
            from: expandedContainerFrame,
            to: collapsedContainerFrame,
            progress: collapseProgress
        )
        dragScrollFrame = CGRect(origin: .zero, size: bounds.size)

        let expandedMaskFrame = CGRect(origin: .zero, size: containerFrame.size)
        let collapsedMaskFrame = CGRect(
            x: inputBarFrame.minX - containerFrame.minX,
            y: inputBarFrame.minY - containerFrame.minY,
            width: inputBarFrame.width,
            height: inputBarFrame.height
        )
        maskFrame = Self.interpolate(
            from: expandedMaskFrame,
            to: collapsedMaskFrame,
            progress: collapseProgress
        )
        maskCornerRadius = max(0, inputBarCornerRadius) * collapseProgress
        hidesAccessibilityElements = collapseProgress >= 0.999
    }

    private static func collapseProgress(
        inputBarWidth: CGFloat,
        expandedInputBarWidth: CGFloat
    ) -> CGFloat {
        let collapsedWidth = OpenAPPInputBar.collapsedMinWidth
        let travel = expandedInputBarWidth - collapsedWidth
        guard travel > 0.5 else {
            return inputBarWidth <= collapsedWidth + 0.5 ? 1 : 0
        }

        let expandedProgress = OpenAPPGeometry.clamp(
            (inputBarWidth - collapsedWidth) / travel,
            0,
            1
        )
        return 1 - expandedProgress
    }

    private static func expandedContainerFrame(
        bounds: CGRect,
        inputBarExpandedFrame _: CGRect
    ) -> CGRect {
        bounds
    }

    private static func interpolate(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: interpolate(from: start.minX, to: end.minX, progress: progress),
            y: interpolate(from: start.minY, to: end.minY, progress: progress),
            width: interpolate(from: start.width, to: end.width, progress: progress),
            height: interpolate(from: start.height, to: end.height, progress: progress)
        )
    }

    private static func interpolate(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * OpenAPPGeometry.clamp(progress, 0, 1)
    }
}

/// `BODragScrollView` 外层的可见窗口：container 只横向收窄，mask 同步变成 inputBar 胶囊。
final class OpenAPPChatPanelContainerView: UIView {
    private let visibleMaskView = UIView()
    private weak var contentView: UIView?
    private var layoutAnimator: UIViewPropertyAnimator?

    var visibleMaskFrame: CGRect { visibleMaskView.frame }
    var visibleMaskCornerRadius: CGFloat { visibleMaskView.layer.cornerRadius }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func installContentView(_ view: UIView) {
        contentView = view
        if view.superview !== self {
            addSubview(view)
        }
    }

    func apply(_ layout: OpenAPPChatPanelContainerLayout, animation: OpenAPPInputBarFrameAnimation) {
        let contentTargetFrame = layout.dragScrollFrame
        let contentFrameChanged = contentView.map {
            !$0.frame.isApproximatelyEqual(to: contentTargetFrame)
        } ?? false
        let targetChanged = !frame.isApproximatelyEqual(to: layout.containerFrame)
            || !visibleMaskView.frame.isApproximatelyEqual(to: layout.maskFrame)
            || abs(visibleMaskView.layer.cornerRadius - layout.maskCornerRadius) > 0.5
            || contentFrameChanged

        accessibilityElementsHidden = layout.hidesAccessibilityElements
        guard targetChanged else { return }

        stopLayoutAnimationAtCurrentState()

        let applyLayout = { [weak self] in
            guard let self else { return }
            self.frame = layout.containerFrame
            self.contentView?.frame = contentTargetFrame
            self.visibleMaskView.frame = layout.maskFrame
            self.visibleMaskView.layer.cornerRadius = layout.maskCornerRadius
            self.accessibilityElementsHidden = layout.hidesAccessibilityElements
        }

        if let animator = animation.makeAnimator(animations: applyLayout) {
            startLayoutAnimation(animator)
        } else {
            applyLayout()
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard containsVisibleMaskPoint(point) else { return nil }
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    private func setup() {
        backgroundColor = .clear
        isAccessibilityElement = false
        visibleMaskView.backgroundColor = .black
        visibleMaskView.isUserInteractionEnabled = false
        visibleMaskView.layer.masksToBounds = true
        mask = visibleMaskView
    }

    private func containsVisibleMaskPoint(_ point: CGPoint) -> Bool {
        let frame = visibleMaskView.layer.presentation()?.frame ?? visibleMaskView.frame
        guard frame.contains(point) else { return false }

        let cornerRadius = visibleMaskView.layer.presentation()?.cornerRadius
            ?? visibleMaskView.layer.cornerRadius
        guard cornerRadius > 0.5 else { return true }
        return UIBezierPath(roundedRect: frame, cornerRadius: cornerRadius).contains(point)
    }

    private func startLayoutAnimation(_ animator: UIViewPropertyAnimator) {
        let identifier = ObjectIdentifier(animator)
        layoutAnimator = animator
        animator.addCompletion { [weak self] _ in
            guard let self,
                  let currentAnimator = self.layoutAnimator,
                  ObjectIdentifier(currentAnimator) == identifier else { return }
            self.layoutAnimator = nil
        }
        animator.startAnimation()
    }

    private func stopLayoutAnimationAtCurrentState() {
        guard let animator = layoutAnimator else { return }
        let containerPresentationFrame = layer.presentation()?.frame
        let contentPresentationFrame = contentView?.layer.presentation()?.frame
        let maskPresentationFrame = visibleMaskView.layer.presentation()?.frame
        let maskPresentationCornerRadius = visibleMaskView.layer.presentation()?.cornerRadius

        layoutAnimator = nil
        animator.stopAnimation(true)
        layer.removeAllAnimations()
        contentView?.layer.removeAllAnimations()
        visibleMaskView.layer.removeAllAnimations()

        if let containerPresentationFrame {
            frame = containerPresentationFrame
        }
        if let contentPresentationFrame {
            contentView?.frame = contentPresentationFrame
        }
        if let maskPresentationFrame {
            visibleMaskView.frame = maskPresentationFrame
        }
        if let maskPresentationCornerRadius {
            visibleMaskView.layer.cornerRadius = maskPresentationCornerRadius
        }
    }
}

#endif
