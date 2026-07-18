//
//  OpenAPPChatPanelGeometry.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

/// 对话流面板可以稳定停靠的三个业务档位。
enum OpenAPPChatPanelDetent: CaseIterable {
    /// 只在 inputBar 上方露出拖拽提示区域。
    case peek

    /// 默认展示约半屏内容。
    case half

    /// 展开到顶部安全区下沿。
    case full
}

/// 一次 ChatPanel 布局所需的不可变几何结果，不包含任何手势或动画决策。
struct OpenAPPChatPanelGeometry: Equatable {

    /// 面板比 inputBar 展开宽度在左右两侧各多出的宽度。
    static let horizontalOutset: CGFloat = 8

    /// 面板顶部两个圆角的半径。
    static let topCornerRadius: CGFloat = 20

    /// 顶部拖拽提示区域的固定高度。
    static let grabBarHeight: CGFloat = 28

    /// peek 状态在 inputBar 顶部额外露出的高度。
    static let peekVisibleHeight: CGFloat = 14

    /// BODragScroll 持有的固定最大面板尺寸。
    let panelSize: CGSize

    /// peek 档对应的实际展示高度。
    let peekHeight: CGFloat

    /// half 档对应的实际展示高度。
    let halfHeight: CGFloat

    /// full 档对应的实际展示高度，同时等于固定面板高度。
    let fullHeight: CGFloat

    /// 根据控制器、安全区和 inputBar 展开宽度生成合法几何；无有效空间时返回 nil。
    init?(
        bounds: CGRect,
        safeAreaInsets: UIEdgeInsets,
        inputBarExpandedFrame: CGRect
    ) {
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let fullHeight = max(0, bounds.height - safeAreaInsets.top)
        guard fullHeight > 0 else { return nil }

        let preferredWidth = inputBarExpandedFrame.width > 0
            ? inputBarExpandedFrame.width + Self.horizontalOutset * 2
            : bounds.width
        let panelWidth = min(bounds.width, max(0, preferredWidth))
        guard panelWidth > 0 else { return nil }

        let peekHeight = min(
            fullHeight,
            max(
                0,
                safeAreaInsets.bottom
                    + OpenAPPInputBar.barHeight
                    + Self.peekVisibleHeight
            )
        )
        let halfHeight = min(fullHeight, max(peekHeight, fullHeight * 0.5))

        panelSize = CGSize(width: panelWidth, height: fullHeight)
        self.peekHeight = peekHeight
        self.halfHeight = halfHeight
        self.fullHeight = fullHeight
    }

    /// 交给 BODragScroll 的已排序、去重档位，避免紧凑窗口中多个业务档位重合。
    var detentHeights: [CGFloat] {
        [peekHeight, halfHeight, fullHeight].reduce(into: []) { result, height in
            guard height > 0 else { return }
            if let last = result.last, abs(last - height) <= 0.5 { return }
            result.append(height)
        }
    }

    /// 返回业务档位在当前几何中的展示高度。
    func height(for detent: OpenAPPChatPanelDetent) -> CGFloat {
        switch detent {
        case .peek:
            return peekHeight
        case .half:
            return halfHeight
        case .full:
            return fullHeight
        }
    }

    /// 将任意展示高度映射到当前几何中距离最近的业务档位。
    ///
    /// 紧凑窗口中多个业务档位可能对应同一个物理高度；距离相同时优先保留原业务档位，
    /// 避免窗口恢复后把原来的 half/full 错误恢复成 peek。
    func nearestDetent(
        to displayHeight: CGFloat,
        preferredDetent: OpenAPPChatPanelDetent? = nil
    ) -> OpenAPPChatPanelDetent {
        let distances = OpenAPPChatPanelDetent.allCases.map { detent in
            (detent: detent, distance: abs(height(for: detent) - displayHeight))
        }
        guard let minimumDistance = distances.map({ $0.distance }).min() else { return .half }

        if let preferredDetent,
           let preferredDistance = distances.first(where: { $0.detent == preferredDetent })?.distance,
           abs(preferredDistance - minimumDistance) <= 0.5 {
            return preferredDetent
        }
        return distances.first(where: { abs($0.distance - minimumDistance) <= 0.5 })?.detent ?? .half
    }

    /// 把布局回调保留下来的旧展示高度约束到新几何的合法范围。
    func clampedDisplayHeight(_ displayHeight: CGFloat) -> CGFloat {
        min(fullHeight, max(peekHeight, displayHeight))
    }
}

#endif
