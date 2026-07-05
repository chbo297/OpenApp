//
//  OpenAPPVoiceWaveformView.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

final class OpenAPPVoiceWaveformView: UIView {
    private static let heightRatios: [CGFloat] = [
        0.24, 0.32, 0.42, 0.55, 0.72, 0.88,
        0.64, 0.50, 0.36, 0.46, 0.62, 0.78,
        0.70, 0.56, 0.42, 0.35, 0.48, 0.60
    ]

    var barColor: UIColor = .black {
        didSet {
            guard !barColor.isEqual(oldValue) else { return }
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        // 绘制思路：用一组固定比例的圆角竖条模拟语音波形。
        // heightRatios 里保存每根竖条相对当前 view 高度的比例，视觉上形成起伏。
        let spacing: CGFloat = 2.5
        let barWidth = max(2, (bounds.width - spacing * CGFloat(Self.heightRatios.count - 1)) / CGFloat(Self.heightRatios.count))
        let maxHeight = bounds.height
        barColor.setFill()

        // 逐根计算 x/y/height，让每根竖条在 Y 轴居中。
        // 使用圆角矩形并把圆角设为 barWidth / 2，让每根条两端都是圆头。
        for (index, ratio) in Self.heightRatios.enumerated() {
            let height = max(6, maxHeight * ratio)
            let x = CGFloat(index) * (barWidth + spacing)
            let y = (bounds.height - height) / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: height)
            UIBezierPath(roundedRect: rect, cornerRadius: barWidth / 2).fill()
        }
    }
}

#endif
