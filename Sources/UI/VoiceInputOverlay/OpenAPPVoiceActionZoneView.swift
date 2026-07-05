//
//  OpenAPPVoiceActionZoneView.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

final class OpenAPPVoiceActionZoneView: UIView {
    enum Side {
        case left
        case right
    }

    var fillColor: UIColor = .clear {
        didSet {
            guard !fillColor.isEqual(oldValue) else { return }
            setNeedsDisplay()
        }
    }

    private let side: Side

    init(side: Side) {
        self.side = side
        super.init(frame: .zero)
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        side = .left
        super.init(coder: coder)
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()

        // 绘制思路：取消和编辑按钮共用一套左侧弧形路径。
        // 右侧按钮不单独写一套坐标，而是把当前绘图上下文水平镜像，保证两侧形状对称。
        if side == .right {
            context.translateBy(x: bounds.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }

        // 按钮视觉不是闭合多边形，而是一条很粗的贝塞尔曲线。
        // 使用 round lineCap / lineJoin 后，曲线两端会自然形成圆头，效果接近弧形胶囊。
        let path = actionPath(in: bounds)
        fillColor.setStroke()
        path.lineWidth = bounds.height * 0.58
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
        context.restoreGState()
    }

    private func actionPath(in rect: CGRect) -> UIBezierPath {
        let width = rect.width
        let height = rect.height
        let strokeWidth = height * 0.58

        // 路径从屏幕外侧开始，向内侧画到接近中间的位置。
        // start 略微放到 bounds 外，可以让按钮看起来像从屏幕边缘伸出来。
        let start = CGPoint(x: -strokeWidth * 0.30, y: height * 0.74)
        let end = CGPoint(x: width * 0.96, y: height * 0.46)
        let mid = CGPoint(x: width * 0.46, y: height * 0.43)

        // 希望曲线经过 mid 这个视觉中点；二次贝塞尔不经过 controlPoint，
        // 所以通过 quadControl(start:end:through:) 反算真正的控制点。
        let path = UIBezierPath()
        path.move(to: start)
        path.addQuadCurve(
            to: end,
            controlPoint: Self.quadControl(start: start, end: end, through: mid)
        )
        return path
    }

    private static func quadControl(start: CGPoint, end: CGPoint, through mid: CGPoint) -> CGPoint {
        // 二次贝塞尔在 t = 0.5 时的位置是 (start + 2 * control + end) / 4。
        // 反过来指定曲线必须经过 mid，就能得到 control = 2 * mid - (start + end) / 2。
        CGPoint(
            x: 2 * mid.x - (start.x + end.x) / 2,
            y: 2 * mid.y - (start.y + end.y) / 2
        )
    }
}

#endif
