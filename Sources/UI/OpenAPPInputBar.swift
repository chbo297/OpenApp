//
//  OpenAPPInputBar.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

// MARK: - Delegate Protocol

public protocol OpenAPPInputBarDelegate: AnyObject {
    func inputBar(_ bar: OpenAPPInputBar, didSendText text: String)
    func inputBarDidTapMenu(_ bar: OpenAPPInputBar)
    func inputBarDidTapVoice(_ bar: OpenAPPInputBar)
    func inputBarDidTapPlus(_ bar: OpenAPPInputBar)
    func inputBarDidRequestExpand(_ bar: OpenAPPInputBar)
}

public extension OpenAPPInputBarDelegate {
    func inputBar(_ bar: OpenAPPInputBar, didSendText text: String) {}
    func inputBarDidTapMenu(_ bar: OpenAPPInputBar) {}
    func inputBarDidTapVoice(_ bar: OpenAPPInputBar) {}
    func inputBarDidTapPlus(_ bar: OpenAPPInputBar) {}
    func inputBarDidRequestExpand(_ bar: OpenAPPInputBar) {}
}

// MARK: - OpenAPPInputBar

/// Presentation-only capsule: lays out subviews from `bounds.width` and `expandedContentWidth`.
/// Until the host sets `expandedContentWidth`, layout uses screen width minus `horizontalInset` as the expanded reference (not `bounds.width`).
/// The host sets `frame` (position, width, keyboard offset). Horizontal collapse/expand pans live on the host, not here.
/// Built-in: text input, buttons, and vertical drag to dismiss the keyboard while the text field is first responder.
public final class OpenAPPInputBar: UIView {

    // MARK: - Layout Constants (shared with host for `frame` math)
    //
    // 图 A · 宿主 view 与胶囊条外框（由 OpenAPPViewController 设置 frame）
    //
    //      |←——— 宿主 view.bounds.width ———→|
    //      |12|←— expandedContentWidth —→|12|
    //         |←—— OpenAPPInputBar ——→|
    //         |← barHeight 56 →|
    //
    //      horizontalInset = 12        → 左右两段「12」
    //      expandedContentWidth = W0    → 中间胶囊条宽度（不含两侧 12）
    //      barHeight = 56               → 胶囊条高度
    //
    // 图 B · 胶囊条内部横向（由 layoutSubviews 排列，单位 pt）
    //
    //      |8| M |8|  文本区域  |8| V |8| + |8|
    //         40     高 36       40    40
    //
    //      innerPadding = 8   → 每一段「8」
    //      buttonSize = 40    → M / V / + 触控区域边长；图标约 26pt
    //      textFieldHeight    → 「文本区域」高度 36
    //      textFieldLeadingVisualOffset = -1 → 文本区整体左移 1（视觉微调，图上未画出）
    //
    // 图 C · 胶囊条圆角（随收起进度线性增大，完全收起 → min(宽,高)/2，两端半圆）
    //
    //      展开  ╭──────────────╮  cornerRadius = 16
    //      收起  ( ● )          cornerRadius → 28（宽 56、高 56 时）
    //
    // 图 D · 完全收起（collapsedMinWidth = 8+40+8 = 56）
    //
    //      |8| M |8|
    //
    // 图 E · 收起三阶段（layoutSubviews）
    //
    //      阶段 1   文本区变窄
    //      阶段 2   V、+ 贴右不动；M 与 V 间距压到 8（条宽 → widthWithUniformButtonGaps）
    //      阶段 3   V 盖住 +，再 M 盖住 V（每步 coverTravel = 48）
    //
    // 图 F · 竖向拖收键盘（与布局无关）
    //
    //      在输入框内竖直拖动 ≥ keyboardDismissAxisThreshold(12) → resignFirstResponder

    /// 图 A：宿主左右留白（pt）。
    public static let horizontalInset: CGFloat = 12

    /// 图 A：胶囊条高度（pt）。
    public static let barHeight: CGFloat = 56

    /// 图 B：条内边距与控件间距（pt）。
    private static let innerPadding: CGFloat = 8

    /// 图 B：menu / voice / plus 边长（pt）。
    private static let buttonSize: CGFloat = 40

    /// 图 B：voice / plus 的 SF Symbol 字号（与 `buttonSize` 同比例放大）。
    private static let symbolIconPointSize: CGFloat = 24

    /// 图 D：完全收起时的条宽（pt）。
    public static var collapsedMinWidth: CGFloat { innerPadding * 2 + buttonSize }

    /// 图 E 前：三按钮间距均为 innerPadding 时的条宽（|8|M|8|V|8|+|8| = 4×8 + 3×40）。
    public static var widthWithUniformButtonGaps: CGFloat {
        innerPadding * 4 + buttonSize * 3
    }

    /// 图 C：展开态圆角（pt）；收起态在 `layoutSubviews` 中插值到 `min(宽,高)/2`。
    private static let expandedCornerRadius: CGFloat = 16

    /// 图 B：文本区 X 微调（pt，负值表示略向左）。
    private let textFieldLeadingVisualOffset: CGFloat = -1

    /// 图 B：文本输入区高度（pt）。
    private let textFieldHeight: CGFloat = 36

    /// 图 F：判定竖向拖动的最小位移（pt）。
    private let keyboardDismissAxisThreshold: CGFloat = 12

    /// 图 E：相邻按钮完全重叠的一档水平行程（pt）。
    private var coverTravel: CGFloat { Self.buttonSize + Self.innerPadding }

    // MARK: - Host-provided layout reference
    //
    // 图 A 中的 W0：宿主 layoutInputBar() 写入；Bar 用来算文本区最大宽度与收起进度。
    // 写入前为 0，临时用「屏幕宽 − 2×horizontalInset」占位。

    /// 图 A：展开态胶囊内容宽度 W0（pt，不含两侧 horizontalInset）。
    public var expandedContentWidth: CGFloat = 0

    /// 宿主是否已写入 W0（expandedContentWidth > 0）。
    public var hasHostExpandedContentWidth: Bool { expandedContentWidth > 0 }

    /// Reference width for collapse math: host value when set, otherwise screen width minus horizontal insets.
    private var effectiveExpandedContentWidth: CGFloat {
        if hasHostExpandedContentWidth { return expandedContentWidth }
        return Self.placeholderExpandedContentWidth(for: self)
    }

    public var isCollapsed: Bool {
        let maxDelta = maxCollapseDelta
        guard maxDelta > 0 else { return false }
        let collapseDelta = max(0, effectiveExpandedContentWidth - bounds.width)
        return collapseDelta >= maxDelta - 0.5
    }

    private var maxCollapseDelta: CGFloat {
        max(0, effectiveExpandedContentWidth - Self.collapsedMinWidth)
    }

    /// 收起进度 0（展开）… 1（完全收起），与 `inputBarCollapseDelta / cap` 一致。
    private var collapseProgress: CGFloat {
        let cap = maxCollapseDelta
        guard cap > 0 else { return 0 }
        let delta = max(0, effectiveExpandedContentWidth - bounds.width)
        return min(1, max(0, delta / cap))
    }

    /// 随 `collapseProgress` 线性增大圆角；完全收起时为 `min(bounds.width, bounds.height) / 2`（整体呈圆形/药丸形）。
    private func updateCapsuleCornerRadius() {
        let collapsedRadius = min(bounds.width, bounds.height) / 2
        let radius = Self.expandedCornerRadius
            + (collapsedRadius - Self.expandedCornerRadius) * collapseProgress
        if abs(layer.cornerRadius - radius) > 0.25 {
            layer.cornerRadius = radius
        }
    }

    /// Placeholder expanded width before the host lays out: `screenWidth - 2×horizontalInset` (not `bounds.width`).
    public static func placeholderExpandedContentWidth(for view: UIView) -> CGFloat {
        let screenWidth: CGFloat
        if let window = view.window {
            screenWidth = window.bounds.width
        } else {
            screenWidth = UIScreen.main.bounds.width
        }
        return max(0, screenWidth - horizontalInset * 2)
    }

    // MARK: - Delegate

    public weak var delegate: OpenAPPInputBarDelegate?

    // MARK: - Subviews

    public let menuButton = OpenAPPMenuButton()
    public let textFieldClipContainer = UIView()
    public let textField = OpenAPPTextField()
    public let voiceButton = UIButton(type: .system)
    public let plusButton = UIButton(type: .system)

    private lazy var keyboardDismissPan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleKeyboardDismissPan(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = self
        return pan
    }()

    // MARK: - Public API

    public var text: String {
        get { textField.text ?? "" }
        set { textField.text = newValue }
    }

    public func clearText() {
        textField.text = ""
    }

    public func setInputEnabled(_ enabled: Bool) {
        textField.isEnabled = enabled
        menuButton.isEnabled = enabled
        voiceButton.isEnabled = enabled
        plusButton.isEnabled = enabled
        updateCollapsedInteractionState()
    }

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private static func systemSymbolImage(primary: String, fallbacks: [String] = []) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: symbolIconPointSize, weight: .regular)
        for name in [primary] + fallbacks {
            if let image = UIImage(systemName: name, withConfiguration: config) {
                return image
            }
        }
        return nil
    }

    private func setup() {
        backgroundColor = .systemBackground
        layer.cornerRadius = Self.expandedCornerRadius
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: -2)

        plusButton.setImage(
            Self.systemSymbolImage(primary: "plus.circle", fallbacks: ["plus"]),
            for: .normal
        )
        plusButton.tintColor = .label
        plusButton.addTarget(self, action: #selector(plusTapped), for: .touchUpInside)

        voiceButton.setImage(
            Self.systemSymbolImage(primary: "microphone.circle", fallbacks: ["microphone"]),
            for: .normal
        )
        voiceButton.tintColor = .label
        voiceButton.addTarget(self, action: #selector(voiceTapped), for: .touchUpInside)

        textFieldClipContainer.clipsToBounds = true

        textField.placeholder = "发消息或按住说话..."
        textField.font = .systemFont(ofSize: 15)
        textField.returnKeyType = .send
        textField.borderStyle = .none
        textField.delegate = self

        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)

        addSubview(plusButton)
        addSubview(voiceButton)
        addSubview(textFieldClipContainer)
        textFieldClipContainer.addSubview(textField)
        addSubview(menuButton)

        addGestureRecognizer(keyboardDismissPan)

        updateCollapsedInteractionState()
    }

    private func updateCollapsedInteractionState() {
        let collapsed = isCollapsed
        textField.isUserInteractionEnabled = textField.isEnabled && !collapsed
        voiceButton.isUserInteractionEnabled = voiceButton.isEnabled && !collapsed && voiceButton.alpha > 0.01
        plusButton.isUserInteractionEnabled = plusButton.isEnabled && !collapsed && plusButton.alpha > 0.01
        textField.alpha = collapsed ? 0 : 1
    }

    /// 展开态参考宽度下，文本裁剪区允许的最大宽度（与当前 `bounds.width` 无关）。
    private func textFieldMaxWidth(atExpandedWidth referenceExpandedWidth: CGFloat) -> CGFloat {
        let textFieldLeadingX = Self.innerPadding + Self.buttonSize + Self.innerPadding + textFieldLeadingVisualOffset
        let plusLeadingXAtExpanded = referenceExpandedWidth - Self.innerPadding - Self.buttonSize
        let voiceLeadingXAtExpanded = plusLeadingXAtExpanded - Self.innerPadding - Self.buttonSize
        return max(0, voiceLeadingXAtExpanded - Self.innerPadding - textFieldLeadingX)
    }

    public override func layoutSubviews() {
        super.layoutSubviews() // 执行系统默认子视图布局
        updateCapsuleCornerRadius() // 圆角随收起进度更新（动画由宿主 layout 驱动）

        let currentBarWidth = bounds.width // 当前胶囊条宽度（宿主设置的 frame.width）
        let currentBarHeight = bounds.height // 当前胶囊条高度
        let referenceExpandedWidth = max(currentBarWidth, effectiveExpandedContentWidth) // 展开态参考宽度（不小于当前宽度）
        let collapseWidthDelta = max(0, referenceExpandedWidth - currentBarWidth) // 比展开态窄了多少 pt
        let menuLeadingX = Self.innerPadding // 菜单按钮展开态左边缘（恒定）
        let textFieldLeadingX = menuLeadingX + Self.buttonSize + Self.innerPadding + textFieldLeadingVisualOffset // 文本裁剪区左边缘
        let textFieldMaxWidthAtExpanded = textFieldMaxWidth(atExpandedWidth: referenceExpandedWidth) // 展开态文本最大可见宽度

        // —— 阶段 1：先收起文本输入区域 ——
        let textFieldShrink = min(collapseWidthDelta, textFieldMaxWidthAtExpanded) // 本阶段消耗的收起量（不超过文本最大宽度）
        let textFieldClipWidth = max(0, textFieldMaxWidthAtExpanded - textFieldShrink) // 文本裁剪容器可见宽度
        var remainingCollapse = max(0, collapseWidthDelta - textFieldShrink) // 文本收完后剩余的收起量

        // —— 阶段 2：压短 menu↔voice 间距（voice、plus 始终贴右；menu 贴左；三键间距均变为 innerPadding）——
        let widthAfterTextCollapse = referenceExpandedWidth - textFieldShrink // 阶段 1 结束时的条宽
        let buttonGapSqueezeTravel = max(0, widthAfterTextCollapse - Self.widthWithUniformButtonGaps) // 本阶段最多消耗的收起量
        let buttonGapSqueezeAmount = min(remainingCollapse, buttonGapSqueezeTravel) // 实际用于压间距的收起量
        remainingCollapse -= buttonGapSqueezeAmount // 间距压到 8 之后剩余的收起量

        // —— 阶段 3：折叠按钮（plus 压 voice，再 menu 压 voice）——
        let buttonOverlapTravel = max(1e-6, coverTravel) // 完全遮盖相邻按钮需滑动的距离（buttonSize + innerPadding）
        let plusOverlapAmount = min(remainingCollapse, buttonOverlapTravel) // 用于 plus 盖住 voice 的收起量
        remainingCollapse -= plusOverlapAmount // 扣除 plus 层已用掉的收起量
        let plusOverlapProgress = plusOverlapAmount / buttonOverlapTravel // plus 覆盖 voice 的进度 0…1

        let voiceOverlapAmount = min(remainingCollapse, buttonOverlapTravel) // 用于 menu 盖住 voice 的收起量
        let voiceOverlapProgress = voiceOverlapAmount / buttonOverlapTravel // menu 覆盖 voice 的进度 0…1

        let buttonCenterY = (currentBarHeight - Self.buttonSize) / 2 // 圆形按钮垂直居中 Y
        let plusTrailingEdge = currentBarWidth - Self.innerPadding // plus 右边缘（距条右 innerPadding）
        let plusLeadingX = plusTrailingEdge - Self.buttonSize // plus 左边缘（贴右，阶段 2 起不变）
        // voice 贴 plus 左侧 innerPadding；阶段 2 仅随条宽右缘内收，阶段 3 再向右叠到 plus 上
        let voiceLeadingXBeforeOverlap = plusLeadingX - Self.innerPadding - Self.buttonSize

        textFieldClipContainer.frame = CGRect(
            x: textFieldLeadingX, // 裁剪容器 X：展开态文本起始位置
            y: (currentBarHeight - textFieldHeight) / 2, // 裁剪容器 Y：文本垂直居中
            width: textFieldClipWidth, // 裁剪容器宽度（随收起变窄）
            height: textFieldHeight // 裁剪容器高度
        )
        textField.frame = CGRect(
            x: 0, // 相对裁剪容器原点
            y: 0,
            width: textFieldMaxWidthAtExpanded, // 内部文本保持展开宽度，由容器裁剪
            height: textFieldHeight // 文本高度
        )

        let voiceLeadingX = voiceLeadingXBeforeOverlap
            + plusOverlapProgress * (plusLeadingX - voiceLeadingXBeforeOverlap) // 阶段 3：voice 向右叠到 plus
        voiceButton.frame = CGRect(
            x: voiceLeadingX, // 语音按钮 X
            y: buttonCenterY, // 语音按钮 Y
            width: Self.buttonSize, // 语音按钮宽
            height: Self.buttonSize // 语音按钮高
        )
        plusButton.frame = CGRect(
            x: plusLeadingX, // 加号按钮 X（贴右）
            y: buttonCenterY,
            width: Self.buttonSize,
            height: Self.buttonSize
        )

        plusButton.alpha = 1 - plusOverlapProgress // plus 被盖住时渐隐（由 voice 在上）
        voiceButton.alpha = 1 - voiceOverlapProgress // voice 被盖住时渐隐（由 menu 在上）

        let menuSlide = voiceOverlapProgress * max(
            0,
            voiceLeadingXBeforeOverlap - menuLeadingX - Self.buttonSize
        ) // 阶段 3：menu 向右推移量（跟随 voice 被盖住的程度）
        let menuLeadingXFinal = menuLeadingX + menuSlide // menu 最终左边缘
        menuButton.frame = CGRect(
            x: menuLeadingXFinal, // 菜单按钮 X
            y: buttonCenterY,
            width: Self.buttonSize,
            height: Self.buttonSize
        )

        updateCollapsedInteractionState() // 收起态：禁用文本/侧键并更新透明度
    }

    @objc private func menuTapped() {
        if isCollapsed {
            delegate?.inputBarDidRequestExpand(self)
            return
        }
        delegate?.inputBarDidTapMenu(self)
    }

    @objc private func voiceTapped() {
        delegate?.inputBarDidTapVoice(self)
    }

    @objc private func plusTapped() {
        delegate?.inputBarDidTapPlus(self)
    }

    @objc private func handleKeyboardDismissPan(_ gr: UIPanGestureRecognizer) {
        guard textField.isFirstResponder else { return }
        let t = gr.translation(in: self)
        switch gr.state {
        case .changed:
            if abs(t.y) >= keyboardDismissAxisThreshold, abs(t.y) >= abs(t.x) * 0.85 {
                textField.resignFirstResponder()
            }
        default:
            break
        }
    }
}

// MARK: - UITextFieldDelegate

extension OpenAPPInputBar: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return true }
        delegate?.inputBar(self, didSendText: text)
        return true
    }
}

// MARK: - UIGestureRecognizerDelegate

extension OpenAPPInputBar: UIGestureRecognizerDelegate {
    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === keyboardDismissPan {
            return textField.isFirstResponder
        }
        return true
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === keyboardDismissPan || otherGestureRecognizer === keyboardDismissPan {
            if otherGestureRecognizer is UIPanGestureRecognizer || gestureRecognizer is UIPanGestureRecognizer {
                return true
            }
            return false
        }
        return true
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

#endif
