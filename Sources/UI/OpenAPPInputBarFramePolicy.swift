//
//  OpenAPPInputBarFramePolicy.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

/// inputBar frame 策略：可用区域、展开/收起首选 frame、拖拽约束、松手落位与吸附。
///
/// 全部为纯函数：环境值经 `Context` 快照传入，输出确定的 frame/决策，不读全局、不碰视图。
/// 持久化经 `OpenAPPInputBarLayoutStoring` 抽象；OpenAPPViewController 只保留状态与接线。
enum OpenAPPInputBarFramePolicy {

    // MARK: - 常量

    /// 宽屏判定阈值：宿主宽度大于该值时，按宽屏 inputBar 策略处理。
    static let wideLayoutWidth: CGFloat = 440

    /// 宽屏默认展开宽度上限：用户未手动调整宽度前，展开态 inputBar 默认最大不超过该值。
    static let wideDefaultMaxWidth: CGFloat = 600

    /// inputBar 与容器左右安全区域之间的水平间距。
    static let horizontalInset: CGFloat = 12

    /// inputBar 避让键盘时与键盘顶部保留的间距，当前为 0 表示紧贴键盘。
    static let keyboardSpacing: CGFloat = 0

    /// 慢速手势阈值：速度绝对值不超过该值时，按“低速/近静止”策略判断最终状态。
    static let slowVelocityThreshold: CGFloat = 50

    /// 快速手势阈值：速度绝对值达到该值时，直接按手势方向决定展开/收起或吸附方向。
    static let fastVelocityThreshold: CGFloat = 650

    /// 中速手势投影系数：用当前速度预估阻尼落点，再根据落点决定最终状态。
    static let projectionFactor: CGFloat = 0.18

    // MARK: - Context

    /// 一次布局决策所需的全部环境值快照。
    struct Context {
        let bounds: CGRect
        let safeAreaInsets: UIEdgeInsets

        /// 生效的键盘避让高度（0 表示不避让）。
        let keyboardHeight: CGFloat

        let storedExpandedWidth: CGFloat?
        let storedCollapsedPlacement: CGPoint?
    }

    // MARK: - 可用区域

    static func availableFrame(in context: Context, avoidingKeyboard: Bool) -> CGRect {
        let bounds = context.bounds
        let safeInsets = context.safeAreaInsets
        let safeTop = safeInsets.top
        let bottom = avoidingKeyboard && context.keyboardHeight > 0
            ? bounds.height - context.keyboardHeight - keyboardSpacing
            : bounds.height - safeInsets.bottom
        let x = safeInsets.left + horizontalInset
        let maxX = max(x, bounds.width - safeInsets.right - horizontalInset)
        return CGRect(
            x: x,
            y: safeTop,
            width: max(0, maxX - x),
            height: max(0, bottom - safeTop)
        )
    }

    static func isWideLayout(_ context: Context) -> Bool {
        context.bounds.width > wideLayoutWidth
    }

    // MARK: - 展开态

    static func defaultExpandedWidth(_ context: Context) -> CGFloat {
        let available = availableFrame(in: context, avoidingKeyboard: true)
        guard isWideLayout(context) else {
            return available.width
        }
        return min(wideDefaultMaxWidth, available.width)
    }

    static func preferredExpandedWidth(_ context: Context) -> CGFloat {
        let available = availableFrame(in: context, avoidingKeyboard: true)
        guard isWideLayout(context) else {
            return available.width
        }

        guard let storedWidth = context.storedExpandedWidth,
              storedWidth >= OpenAPPInputBar.minimumExpandedWidth else {
            return defaultExpandedWidth(context)
        }

        return clampedExpandedWidth(storedWidth, context: context)
    }

    static func preferredExpandedFrame(_ context: Context) -> CGRect {
        expandedFrame(width: preferredExpandedWidth(context), context: context)
    }

    static func expandedFrame(width: CGFloat, context: Context) -> CGRect {
        let available = availableFrame(in: context, avoidingKeyboard: true)
        let clampedWidth = clampedExpandedWidth(width, context: context)
        let x = available.midX - clampedWidth / 2
        return CGRect(
            x: x,
            y: max(available.minY, available.maxY - OpenAPPInputBar.barHeight),
            width: clampedWidth,
            height: OpenAPPInputBar.barHeight
        )
    }

    static func clampedExpandedWidth(_ width: CGFloat, context: Context) -> CGFloat {
        let availableWidth = availableFrame(in: context, avoidingKeyboard: true).width
        guard availableWidth > 0 else { return 0 }
        let minWidth = min(OpenAPPInputBar.minimumExpandedWidth, availableWidth)
        return OpenAPPGeometry.clamp(width, minWidth, availableWidth)
    }

    static func constrainedExpandedFrame(_ proposedFrame: CGRect, context: Context) -> CGRect {
        let available = availableFrame(in: context, avoidingKeyboard: true)
        let width = OpenAPPGeometry.clamp(
            proposedFrame.width,
            OpenAPPInputBar.collapsedMinWidth,
            max(OpenAPPInputBar.collapsedMinWidth, available.width)
        )
        let minX = available.minX
        let maxX = max(available.minX, available.maxX - width)
        let x = OpenAPPGeometry.clamp(proposedFrame.maxX - width, minX, maxX)
        let y = max(available.minY, available.maxY - OpenAPPInputBar.barHeight)
        return CGRect(x: x, y: y, width: width, height: OpenAPPInputBar.barHeight)
    }

    /// 可持久化的展开宽度：仅宽屏且宽度有效时返回截断后的值，否则 nil。
    static func storableExpandedWidth(_ width: CGFloat, context: Context) -> CGFloat? {
        let availableWidth = availableFrame(in: context, avoidingKeyboard: true).width
        guard isWideLayout(context),
              availableWidth >= OpenAPPInputBar.minimumExpandedWidth,
              width >= OpenAPPInputBar.minimumExpandedWidth else {
            return nil
        }
        return OpenAPPGeometry.clamp(width, OpenAPPInputBar.minimumExpandedWidth, availableWidth)
    }

    /// 松手结算：展开 resize 结束时是否应收起（快速甩动按方向，中速按投影落点，低速按当前宽度）。
    static func shouldCollapseExpanded(velocityX vx: CGFloat, frame: CGRect, context: Context) -> Bool {
        let minWidth = OpenAPPInputBar.collapsedMinWidth
        let maxWidth = preferredExpandedWidth(context)
        let speed = abs(vx)

        guard frame.width >= OpenAPPInputBar.minimumExpandedWidth else {
            return true
        }

        if speed >= fastVelocityThreshold {
            return vx > 0
        }

        let decisionWidth: CGFloat
        if speed <= slowVelocityThreshold {
            decisionWidth = frame.width
        } else {
            decisionWidth = OpenAPPGeometry.clamp(
                frame.width - vx * projectionFactor,
                minWidth,
                maxWidth
            )
        }
        if decisionWidth < OpenAPPInputBar.minimumExpandedWidth {
            return true
        }
        return decisionWidth < (minWidth + maxWidth) * 0.5
    }

    // MARK: - 收起态

    static func defaultCollapsedFrame(_ context: Context) -> CGRect {
        let available = availableFrame(in: context, avoidingKeyboard: false)
        let width = OpenAPPInputBar.collapsedMinWidth
        return CGRect(
            x: max(available.minX, available.maxX - width),
            y: max(available.minY, available.maxY - OpenAPPInputBar.barHeight),
            width: width,
            height: OpenAPPInputBar.barHeight
        )
    }

    static func preferredCollapsedFrame(_ context: Context) -> CGRect {
        guard let placement = context.storedCollapsedPlacement else {
            return defaultCollapsedFrame(context)
        }
        return constrainedCollapsedFrame(
            collapsedFrame(fromStoredPlacement: placement, context: context),
            context: context
        )
    }

    /// 从持久化位置恢复 frame：placement 的正/负号分别表示相对可用区左上/右下的偏移。
    static func collapsedFrame(fromStoredPlacement placement: CGPoint, context: Context) -> CGRect {
        let available = availableFrame(in: context, avoidingKeyboard: false)
        let width = OpenAPPInputBar.collapsedMinWidth
        let height = OpenAPPInputBar.barHeight
        let x = placement.x.sign == .minus
            ? available.maxX - width + placement.x
            : available.minX + placement.x
        let y = placement.y.sign == .minus
            ? available.maxY - height + placement.y
            : available.minY + placement.y
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func constrainedCollapsedFrame(_ proposedFrame: CGRect, context: Context) -> CGRect {
        let available = availableFrame(in: context, avoidingKeyboard: false)
        let width = OpenAPPInputBar.collapsedMinWidth
        let height = OpenAPPInputBar.barHeight
        let maxX = max(available.minX, available.maxX - width)
        let maxY = max(available.minY, available.maxY - height)
        return CGRect(
            x: OpenAPPGeometry.clamp(proposedFrame.minX, available.minX, maxX),
            y: OpenAPPGeometry.clamp(proposedFrame.minY, available.minY, maxY),
            width: width,
            height: height
        )
    }

    /// frame → 可持久化位置：取较近的一侧记偏移，负号（含 -0.0）表示相对右/下边。
    static func collapsedPlacement(for frame: CGRect, context: Context) -> CGPoint {
        let available = availableFrame(in: context, avoidingKeyboard: false)
        let leftOffset = frame.minX - available.minX
        let rightOffset = trailingPlacementOffset(frame.minX - (available.maxX - frame.width))
        let topOffset = frame.minY - available.minY
        let bottomOffset = trailingPlacementOffset(frame.minY - (available.maxY - frame.height))
        let x = leftOffset <= abs(rightOffset) ? leftOffset : rightOffset
        let y = topOffset <= abs(bottomOffset) ? topOffset : bottomOffset
        return CGPoint(x: x, y: y)
    }

    static func trailingPlacementOffset(_ offset: CGFloat) -> CGFloat {
        offset == 0 ? CGFloat(-0.0) : offset
    }

    /// 松手结算：收起态 move 结束后的吸附落点（快速甩动按方向吸边，其余按投影落点选最近边）。
    static func collapsedSnapFrame(velocity: CGPoint, frame: CGRect, context: Context) -> CGRect {
        let available = availableFrame(in: context, avoidingKeyboard: false)
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
        let allowsBottomSnap = isWideLayout(context)

        if allowsBottomSnap,
           velocity.y >= fastVelocityThreshold,
           velocityY >= velocityX {
            return constrainedCollapsedFrame(bottomFrame, context: context)
        }

        if velocityX >= fastVelocityThreshold {
            return constrainedCollapsedFrame(velocity.x < 0 ? leftFrame : rightFrame, context: context)
        }

        guard allowsBottomSnap else {
            let projectedCenterX = frame.midX + velocity.x * projectionFactor
            let shouldSnapLeft = abs(projectedCenterX - leftFrame.midX) <= abs(projectedCenterX - rightFrame.midX)
            return constrainedCollapsedFrame(shouldSnapLeft ? leftFrame : rightFrame, context: context)
        }

        let projectedCenter = CGPoint(
            x: frame.midX + velocity.x * projectionFactor,
            y: frame.midY + velocity.y * projectionFactor
        )
        func distanceSquared(to candidate: CGRect) -> CGFloat {
            let dx = projectedCenter.x - candidate.midX
            let dy = projectedCenter.y - candidate.midY
            return dx * dx + dy * dy
        }

        let targetFrame = [leftFrame, rightFrame, bottomFrame].min {
            distanceSquared(to: $0) < distanceSquared(to: $1)
        } ?? rightFrame
        return constrainedCollapsedFrame(targetFrame, context: context)
    }
}

// MARK: - 持久化

/// inputBar 布局偏好的持久化抽象：策略层不关心存储介质。
protocol OpenAPPInputBarLayoutStoring {
    func loadExpandedWidth() -> CGFloat?
    func saveExpandedWidth(_ width: CGFloat)
    func loadCollapsedPlacement() -> CGPoint?
    func saveCollapsedPlacement(_ placement: CGPoint)
}

/// 默认实现：UserDefaults。
struct OpenAPPUserDefaultsInputBarLayoutStore: OpenAPPInputBarLayoutStoring {
    static let expandedWidthKey = "com.openapp.ui.inputBar.wideExpandedWidth"
    static let collapsedPlacementKey = "com.openapp.ui.inputBar.collapsedPlacementXY"

    var defaults: UserDefaults = .standard

    func loadExpandedWidth() -> CGFloat? {
        guard defaults.object(forKey: Self.expandedWidthKey) != nil else {
            return nil
        }

        let width = CGFloat(defaults.double(forKey: Self.expandedWidthKey))
        guard width.isFinite, width >= OpenAPPInputBar.minimumExpandedWidth else {
            return nil
        }
        return width
    }

    func saveExpandedWidth(_ width: CGFloat) {
        defaults.set(Double(width), forKey: Self.expandedWidthKey)
    }

    func loadCollapsedPlacement() -> CGPoint? {
        guard let value = defaults.string(forKey: Self.collapsedPlacementKey) else {
            return nil
        }
        return Self.parsePlacement(value)
    }

    func saveCollapsedPlacement(_ placement: CGPoint) {
        defaults.set(Self.encodePlacement(placement), forKey: Self.collapsedPlacementKey)
    }

    static func parsePlacement(_ value: String) -> CGPoint? {
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

    static func encodePlacement(_ placement: CGPoint) -> String {
        "\(Double(placement.x)),\(Double(placement.y))"
    }
}

#endif
