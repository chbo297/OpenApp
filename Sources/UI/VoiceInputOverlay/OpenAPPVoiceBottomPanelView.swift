//
//  OpenAPPVoiceBottomPanelView.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

final class OpenAPPVoiceBottomPanelView: UIView {
    private static let topHitExpansion: CGFloat = 8
    private static let selectionAnimationDuration: TimeInterval = 0.12
    private static let normalVerticalOffset: CGFloat = 10
    private static let sideY: CGFloat = 40
    private static let selectedFillColor = UIColor(red: 0.84, green: 0.85, blue: 0.84, alpha: 1)
    private static let normalFillColor = UIColor(red: 0.30, green: 0.30, blue: 0.29, alpha: 1)
    private static let selectedPromptColor = UIColor.black.withAlphaComponent(0.82)
    private static let normalPromptColor = UIColor.white.withAlphaComponent(0.82)
    private static let selectedPromptText = "松开 发送"
    private static let normalPromptText = "语音"

    private let promptLabel = UILabel()
    private var isPanelSelected = false
    private var fillColor = OpenAPPVoiceBottomPanelView.normalFillColor
    private var cachedPanelBounds: CGRect = .null
    private var cachedPanelPath: UIBezierPath?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setSelected(_ selected: Bool) {
        guard isPanelSelected != selected else { return }
        isPanelSelected = selected
        updateAppearance(animated: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if cachedPanelBounds != bounds {
            invalidatePanelPathCache()
        }
        promptLabel.frame = CGRect(
            x: 0,
            y: 4,
            width: bounds.width,
            height: 36
        )
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        fillColor.setFill()
        cachedPanelPath(for: bounds).fill()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard bounds.width > 0, bounds.height > 0 else { return false }
        let panelPath = cachedPanelPath(for: bounds)
        if panelPath.contains(point) {
            return true
        }

        // 手指判定：允许手指在底部面板弧线上方 8pt 内也算进入发送区域；
        // 这里保留原始路径判断，再额外判断上扩区域，避免把面板底部 8pt 误排除。
        let topExpandedPoint = CGPoint(x: point.x, y: point.y + Self.topHitExpansion)
        return panelPath.contains(topExpandedPoint)
    }

    private func setup() {
        backgroundColor = .clear
        promptLabel.textAlignment = .center
        promptLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        addSubview(promptLabel)
        updateAppearance(animated: false)
    }

    private func updateAppearance(animated: Bool) {
        updatePromptText(animated: animated)
        fillColor = isPanelSelected ? Self.selectedFillColor : Self.normalFillColor
        setNeedsDisplay()

        let updates = {
            self.transform = self.isPanelSelected
                ? .identity
                : CGAffineTransform(translationX: 0, y: Self.normalVerticalOffset)
            self.promptLabel.textColor = self.isPanelSelected
                ? Self.selectedPromptColor
                : Self.normalPromptColor
        }

        guard animated else {
            updates()
            return
        }

        UIView.animate(
            withDuration: Self.selectionAnimationDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
            animations: updates
        )
    }

    private func updatePromptText(animated: Bool) {
        let text = isPanelSelected ? Self.selectedPromptText : Self.normalPromptText
        guard animated else {
            promptLabel.text = text
            return
        }

        UIView.transition(
            with: promptLabel,
            duration: Self.selectionAnimationDuration,
            options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState],
            animations: {
                self.promptLabel.text = text
            }
        )
    }

    private func invalidatePanelPathCache() {
        cachedPanelBounds = .null
        cachedPanelPath = nil
    }

    private func cachedPanelPath(for rect: CGRect) -> UIBezierPath {
        if cachedPanelBounds == rect, let cachedPanelPath {
            return cachedPanelPath
        }

        // draw(_:) 首次绘制或尺寸变化后生成路径并缓存；
        // point(inside:with:) 高频命中测试直接复用这条路径，避免拖拽过程中重复构造贝塞尔曲线。
        let path = makePanelPath(in: rect)
        cachedPanelBounds = rect
        cachedPanelPath = path
        return path
    }

    private func makePanelPath(in rect: CGRect) -> UIBezierPath {
        let width = rect.width

        // 绘制思路：底部面板是一个从屏幕底部向上露出的不透明区域。
        // 先确定左右两侧与上边缘相交的位置 sideY，再让弧线中间最高点贴住 bounds.minY。
        // 未选中态不改贝塞尔曲线本身，而是用 transform 将整个面板向下移动 10pt。
        // 二次贝塞尔曲线不会直接经过 controlPoint，所以这里用目标中点 apexY 反算 controlY。
        let sideY = Self.sideY
        let apexY: CGFloat = 0
        let controlY = 2 * apexY - sideY

        // 路径顺序：左下角 -> 左侧弧线起点 -> 二次贝塞尔弧线到右侧起点 -> 右下角 -> 闭合。
        // draw(_:) 和 point(inside:with:) 共用缓存路径，保证“显示出来的区域”和“发送判定区域”一致。
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + sideY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + sideY),
            controlPoint: CGPoint(x: rect.minX + width * 0.5, y: rect.minY + controlY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.close()
        return path
    }
}

#endif
