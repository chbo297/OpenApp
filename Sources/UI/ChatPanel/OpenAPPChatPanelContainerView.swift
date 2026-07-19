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
        // 取出内部 BODragScroll 内容视图应该使用的目标 frame。
        let contentTargetFrame = layout.dragScrollFrame

        // 记录内部内容视图的 frame 是否发生变化。
        let contentFrameChanged: Bool
        // 如果已经安装了内容视图，就拿它当前 frame 和目标 frame 比较。
        if let contentView {
            // 用近似比较避免浮点小误差导致重复布局。
            contentFrameChanged = !contentView.frame.isApproximatelyEqual(to: contentTargetFrame)
        } else {
            // 如果还没有安装内容视图，就认为内容 frame 没有变化。
            contentFrameChanged = false
        }

        // 判断外层 container 的 frame 是否需要变化。
        let containerFrameChanged = !frame.isApproximatelyEqual(to: layout.containerFrame)
        // 判断 mask 的可见区域是否需要变化。
        let maskFrameChanged = !visibleMaskView.frame.isApproximatelyEqual(to: layout.maskFrame)
        // 判断 mask 圆角是否需要变化，0.5 以内的小差异直接忽略。
        let maskCornerRadiusChanged = abs(visibleMaskView.layer.cornerRadius - layout.maskCornerRadius) > 0.5
        // 只要 container、mask、圆角或内部内容任意一项变化，就需要重新应用布局。
        let targetChanged = containerFrameChanged
            || maskFrameChanged
            || maskCornerRadiusChanged
            || contentFrameChanged

        // 先同步无障碍隐藏状态；即使 frame 没变，也要保证折叠态不会被 VoiceOver 读到。
        accessibilityElementsHidden = layout.hidesAccessibilityElements
        // 如果所有目标值都没变，就直接返回，避免创建无意义动画。
        guard targetChanged else { return }

        // 如果上一个布局动画还在跑，先停在当前视觉位置，避免新旧动画打架。
        stopLayoutAnimationAtCurrentState()

        // 把真正要改 frame/mask 的操作封装成闭包，方便立即执行或交给 animator 执行。
        let applyLayout = { [weak self] in
            // 动画闭包可能晚于 view 生命周期执行，所以用 weak self 防止循环引用。
            guard let self else { return }
            // 更新外层可见窗口的位置和尺寸。
            self.frame = layout.containerFrame
            // 更新内部 BODragScroll 内容视图尺寸；当前保持 x/y 为 0，让它跟随 container 移动。
            self.contentView?.frame = contentTargetFrame
            // 更新 mask 的 frame，决定 container 内部哪些区域真正可见。
            self.visibleMaskView.frame = layout.maskFrame
            // 更新 mask 圆角，让收起时逐步变成 inputBar 胶囊形状。
            self.visibleMaskView.layer.cornerRadius = layout.maskCornerRadius
            // 再同步一次无障碍隐藏状态，保证动画执行后状态仍正确。
            self.accessibilityElementsHidden = layout.hidesAccessibilityElements
        }

        // 如果当前变化需要动画，就用 inputBar 同一套动画参数驱动 container/mask。
        if let animator = animation.makeAnimator(animations: applyLayout) {
            // 持有并启动 animator，后续新手势可以从当前动画位置接管。
            startLayoutAnimation(animator)
        } else {
            // 拖拽跟手或普通布局刷新不需要动画，直接应用目标布局。
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
