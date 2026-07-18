//
//  OpenAPPChatPanelCoordinator.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import BODragScroll
import UIKit

/// ChatPanel 与 BODragScroll 之间的唯一适配层。
///
/// 该对象拥有拖拽容器和固定尺寸面板，负责尺寸提供、detent、内部列表捕获、程序化移动以及
/// 运动结束后的列表可见区同步。业务消息和 inputBar/键盘策略仍由 OpenAPPViewController 管理。
@MainActor
final class OpenAPPChatPanelCoordinator: NSObject {

    /// 铺满 OpenAPPViewController、但只在可见 panel 范围内命中触摸的拖拽容器。
    let dragScrollView = BODragScrollView(frame: .zero)

    /// 由 BODragScroll 固定尺寸承载的业务内容视图。
    let panelView = OpenAPPChatPanelView()

    /// 最近一次稳定落位对应的业务档位，用于尺寸变化时保持语义位置。
    private var settledDetent: OpenAPPChatPanelDetent = .half

    private var geometry: OpenAPPChatPanelGeometry?
    private var pendingLayoutDetent: OpenAPPChatPanelDetent?
    private var bottomAvoidingInset: CGFloat = 0
    private var settlementSynchronizationGeneration: UInt = 0

    override init() {
        super.init()

        dragScrollView.backgroundColor = .clear
        dragScrollView.behaviorProvider = self
        dragScrollView.eventDelegate = self

        var configuration = dragScrollView.configuration
        configuration.handoff.mode = .coordinated
        configuration.handoff.offsetMismatch = .waitForValidSegment
        configuration.handoff.preventsInnerToPanelHandoff = false
        dragScrollView.configuration = configuration
    }

    /// 根据 ViewController 最新环境更新 host、固定面板尺寸和 detent。
    func updateLayout(
        bounds: CGRect,
        safeAreaInsets: UIEdgeInsets,
        inputBarExpandedFrame: CGRect,
        bottomAvoidingInset: CGFloat
    ) {
        self.bottomAvoidingInset = max(0, bottomAvoidingInset)
        dragScrollView.frame = CGRect(origin: .zero, size: bounds.size)

        guard let newGeometry = OpenAPPChatPanelGeometry(
            bounds: bounds,
            safeAreaInsets: safeAreaInsets,
            inputBarExpandedFrame: inputBarExpandedFrame
        ) else { return }

        guard geometry != newGeometry else {
            synchronizeSettledStateIfPossible()
            return
        }

        let isFirstGeometry = geometry == nil
        geometry = newGeometry
        if isFirstGeometry {
            // 首次布局前若业务已经调用 move(to:)，保留该请求；否则默认停在 half。
            pendingLayoutDetent = pendingLayoutDetent ?? settledDetent
        } else {
            pendingLayoutDetent = settledDetent
        }
        dragScrollView.detentHeights = newGeometry.detentHeights

        if dragScrollView.panelView == nil {
            // provider、configuration 和 detent 必须先就绪，最后赋 panelView 才能得到正确首次布局。
            dragScrollView.panelView = panelView
        } else {
            dragScrollView.invalidatePanelLayout()
        }

        dragScrollView.setNeedsLayout()
        dragScrollView.layoutIfNeeded()
        synchronizeSettledStateIfPossible()
    }

    /// 更新悬浮 inputBar、safe area 或键盘占用的底部空间。
    func updateBottomAvoidingInset(_ inset: CGFloat) {
        let normalizedInset = max(0, inset)
        guard abs(normalizedInset - bottomAvoidingInset) > 0.5 else { return }
        bottomAvoidingInset = normalizedInset
        synchronizeSettledStateIfPossible()
    }

    /// 由业务主动移动到指定档位；运动细节和中途打断全部交给 BODragScroll。
    func move(to detent: OpenAPPChatPanelDetent, animated: Bool) {
        guard let geometry else {
            settledDetent = detent
            pendingLayoutDetent = detent
            return
        }

        dragScrollView.move(
            toDisplayHeight: geometry.height(for: detent),
            animated: animated
        ) { [weak self] result in
            guard result.outcome == .completed else { return }
            self?.scheduleSettledStateSynchronization()
        }
    }

    /// 当前是否稳定处在 peek 附近，供新消息到达时决定是否自动展开。
    var isAtPeekDetent: Bool {
        guard let geometry else { return settledDetent == .peek }
        guard dragScrollView.displayHeight > 0 else { return settledDetent == .peek }
        return geometry.nearestDetent(
            to: dragScrollView.displayHeight,
            preferredDetent: settledDetent
        ) == .peek
    }

    private var isMovementActive: Bool {
        dragScrollView.isTracking
            || dragScrollView.isDragging
            || dragScrollView.isDecelerating
            || dragScrollView.isAnimatingDisplayHeight
    }

    /// 运动中冻结 tableView 指标；稳定后只提交一次可见区补偿并重建滚动模型。
    private func synchronizeSettledStateIfPossible() {
        guard !isMovementActive else { return }
        synchronizeSettledState(at: dragScrollView.displayHeight)
    }

    private func synchronizeSettledState(at displayHeight: CGFloat) {
        guard let geometry, displayHeight > 0 else { return }

        settledDetent = geometry.nearestDetent(
            to: displayHeight,
            preferredDetent: settledDetent
        )
        let stableDisplayHeight = geometry.height(for: settledDetent)
        let metricsChanged = panelView.listView.updateViewport(
            panelHeight: geometry.fullHeight,
            displayHeight: stableDisplayHeight,
            bottomAvoidingInset: bottomAvoidingInset
        )
        if metricsChanged {
            dragScrollView.reloadScrollMetrics()
        }
    }

    /// 避开 BODragScroll 自己的同步 delegate 调用栈，再读取最终几何并更新列表指标。
    private func scheduleSettledStateSynchronization() {
        settlementSynchronizationGeneration &+= 1
        let generation = settlementSynchronizationGeneration
        Task { @MainActor [weak self] in
            guard let self, generation == self.settlementSynchronizationGeneration else { return }
            self.synchronizeSettledStateIfPossible()
        }
    }
}

// MARK: - BODragScrollBehaviorProvider

extension OpenAPPChatPanelCoordinator: BODragScrollBehaviorProvider {
    func dragScrollView(
        _ dragScrollView: BODragScrollView,
        sizeFor panelView: UIView,
        firstLayout: Bool,
        proposedDisplayHeight: inout CGFloat
    ) -> CGSize? {
        guard panelView === self.panelView, let geometry else { return nil }

        if let pendingLayoutDetent {
            proposedDisplayHeight = geometry.height(for: pendingLayoutDetent)
            self.pendingLayoutDetent = nil
        } else if firstLayout {
            proposedDisplayHeight = geometry.halfHeight
        } else {
            proposedDisplayHeight = geometry.clampedDisplayHeight(proposedDisplayHeight)
        }
        return geometry.panelSize
    }

    func dragScrollView(
        _ dragScrollView: BODragScrollView,
        segmentsFor scrollView: UIScrollView
    ) -> [BODragScrollInnerScrollSegment]? {
        guard scrollView === panelView.listView.participantScrollView,
              let geometry else { return nil }
        return [.init(displayHeight: geometry.fullHeight)]
    }

    func dragScrollView(
        _ dragScrollView: BODragScrollView,
        canCapture scrollView: UIScrollView
    ) -> Bool {
        scrollView === panelView.listView.participantScrollView
    }
}

// MARK: - BODragScrollEventDelegate

extension OpenAPPChatPanelCoordinator: BODragScrollEventDelegate {
    func dragScrollView(
        _ dragScrollView: BODragScrollView,
        didFinishMovement result: BODragScrollMovementResult
    ) {
        guard result.outcome == .completed else { return }
        scheduleSettledStateSynchronization()
    }

    func dragScrollViewDidEndDragging(
        _ dragScrollView: BODragScrollView,
        willDecelerate: Bool
    ) {
        guard !willDecelerate else { return }
        scheduleSettledStateSynchronization()
    }

    func dragScrollViewDidEndDecelerating(_ dragScrollView: BODragScrollView) {
        scheduleSettledStateSynchronization()
    }

    func dragScrollViewDidEndScrollingAnimation(_ dragScrollView: BODragScrollView) {
        scheduleSettledStateSynchronization()
    }
}

#endif
