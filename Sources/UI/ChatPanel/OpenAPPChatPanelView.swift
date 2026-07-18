//
//  OpenAPPChatPanelView.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

/// 对话流面板卡片视图：顶部圆角 + 顶栏拖拽条 + 聊天内容区。
///
/// 自身只负责固定最大尺寸内的视觉布局；展示高度、拖拽、吸附和内部滚动交接全部由
/// `OpenAPPChatPanelCoordinator` 持有的 BODragScrollView 管理。
final class OpenAPPChatPanelView: UIView {

    /// 聊天内容区，消息的追加/流式更新由宿主直接操作。
    let listView = OpenAPPChatMessageListView()

    private let cardView = UIView()
    private let grabberView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        cardView.frame = bounds
        grabberView.frame = CGRect(
            x: (bounds.width - 36) / 2,
            y: 6,
            width: 36,
            height: 5
        )
        listView.frame = CGRect(
            x: 0,
            y: OpenAPPChatPanelGeometry.grabBarHeight,
            width: bounds.width,
            height: max(0, bounds.height - OpenAPPChatPanelGeometry.grabBarHeight)
        )
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyAppearance()
    }

    // MARK: - 内部

    private func setup() {
        backgroundColor = .clear
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: -4)

        // 卡片承载圆角裁剪，阴影留在自身 layer 上，两者互不牺牲。
        cardView.layer.cornerRadius = OpenAPPChatPanelGeometry.topCornerRadius
        cardView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        cardView.clipsToBounds = true
        addSubview(cardView)

        cardView.addSubview(listView)

        grabberView.layer.cornerRadius = 2.5
        cardView.addSubview(grabberView)

        applyAppearance()
    }

    private func applyAppearance() {
        cardView.backgroundColor = OpenAPPAppearance.inputBarBackground
        grabberView.backgroundColor = OpenAPPAppearance.placeholderText
        layer.shadowColor = OpenAPPAppearance.inputBarShadow.resolvedColor(with: traitCollection).cgColor
        layer.shadowOpacity = OpenAPPAppearance.inputBarShadowOpacity(for: traitCollection)
    }

}

#endif
