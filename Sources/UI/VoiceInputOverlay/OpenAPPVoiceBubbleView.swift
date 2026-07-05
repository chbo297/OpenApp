//
//  OpenAPPVoiceBubbleView.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

final class OpenAPPVoiceBubbleView: UIView {
    var fillColor: UIColor = .clear {
        didSet {
            guard !fillColor.isEqual(oldValue) else { return }
            setNeedsDisplay()
        }
    }

    var cornerRadius: CGFloat = 16 {
        didSet {
            guard abs(cornerRadius - oldValue) > 0.25 else { return }
            setNeedsDisplay()
        }
    }

    var tailXRatio: CGFloat = 0.5 {
        didSet {
            guard abs(tailXRatio - oldValue) > 0.001 else { return }
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let tailHeight: CGFloat = 16
        let tailWidth: CGFloat = 24

        // 绘制思路：气泡由上方圆角矩形主体和底部三角尾巴组成。
        // 主体高度需要扣掉 tailHeight，给尾巴留出绘制空间。
        let body = bounds.insetBy(dx: 0, dy: 0).divided(atDistance: bounds.height - tailHeight, from: .minYEdge).slice
        let path = UIBezierPath(roundedRect: body, cornerRadius: cornerRadius)

        // 尾巴位置由 tailXRatio 控制，但需要夹在左右圆角内，避免尾巴压到圆角区域。
        let tailCenterX = Self.clamp(
            bounds.width * tailXRatio,
            cornerRadius + tailWidth / 2,
            bounds.width - cornerRadius - tailWidth / 2
        )

        // 尾巴用一个向下的三角形表示，稍微与主体重叠 1pt，避免抗锯齿导致缝隙。
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: tailCenterX - tailWidth / 2, y: body.maxY - 1))
        tail.addLine(to: CGPoint(x: tailCenterX, y: body.maxY + tailHeight))
        tail.addLine(to: CGPoint(x: tailCenterX + tailWidth / 2, y: body.maxY - 1))
        tail.close()
        path.append(tail)
        fillColor.setFill()
        path.fill()
    }

    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        guard hi >= lo else { return lo }
        return min(hi, max(lo, v))
    }
}

#endif
