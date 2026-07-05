//
//  OpenAPPViewController.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

/// OpenAPPViewController 实际应用 inputBar frame 变化的原因。
public enum OpenAPPInputBarFrameChangeReason {
    /// 场景：`viewDidLayoutSubviews` 或容器尺寸变化时，OpenAPPViewController 主动重新计算并应用 inputBar frame。
    case layout

    /// 场景：inputBar 自己的 textField 激活/失焦，或键盘高度变化后，需要根据键盘避让策略重新应用 inputBar frame。
    case keyboard

    /// 场景：收起态点击 menu 按钮、手势结算判定为展开，或外部主动请求展开 inputBar。
    case expand

    /// 场景：展开态点击 menu 按钮、手势结算判定为收起，或外部主动请求收起 inputBar。
    case collapse

    /// 场景：展开态从 menu 按钮起手横向拖拽 resize，inputBar 跟随手指实时改变宽度。
    case expandedResizePan

    /// 场景：收起态从 menu 按钮起手拖拽移动，inputBar 跟随手指实时改变位置。
    case collapsedMovePan

    /// 场景：收起态拖拽结束后，根据稳定停留、速度和吸附策略计算最终落点并应用 frame。
    case collapsedMoveResolution
}

/// OpenAPPViewController 完成 inputBar frame 应用后对外通知的上下文。
public struct OpenAPPInputBarFrameChangeContext {
    public let reason: OpenAPPInputBarFrameChangeReason
    public let oldFrame: CGRect
    public let newFrame: CGRect
    public let animated: Bool

    public init(
        reason: OpenAPPInputBarFrameChangeReason,
        oldFrame: CGRect,
        newFrame: CGRect,
        animated: Bool
    ) {
        self.reason = reason
        self.oldFrame = oldFrame
        self.newFrame = newFrame
        self.animated = animated
    }
}

/// Main view controller for OpenAPP chat interface.
/// Hosts a message list (tableView) and an input bar (OpenAPPInputBar).
/// Intended to be used as the rootViewController of an `OpenAPPWindow`.
/// All layout is done via manual frames in `viewDidLayoutSubviews`.
open class OpenAPPViewController: UIViewController {

    // MARK: - Public API

    /// 是否打印 inputBar delegate 调试日志；默认关闭，避免拖拽和语音手势 changed 阶段产生高频控制台 I/O。
    public static var isInputBarDelegateDebugLoggingEnabled = false

    /// The agent powering this chat.
    public var agent: AIAgent?

    /// inputBar frame 被 OpenAPPViewController 实际应用后触发，宿主可用它观察键盘、展开、收起和拖拽导致的位置变化。
    public var onInputBarFrameChange: ((OpenAPPInputBarFrameChangeContext) -> Void)?

    /// The currently displayed session ID.
    public private(set) var currentSessionId: String?

    /// Convenience: the current session object.
    public var currentSession: AISession? {
        guard let id = currentSessionId else { return nil }
        return agent?.session(id: id)
    }

    /// Switch to a different session.
    public func switchSession(to sessionId: String) {
        currentStreamTask?.cancel()
        currentStreamTask = nil
        currentSession?.uiState.onChange = nil
        currentSessionId = sessionId
        reloadFromSession()
        bindUIState()
    }

    /// 子类可 override 观察 inputBar frame 变化。
    open func inputBarFrameDidChange(_ context: OpenAPPInputBarFrameChangeContext) {}

    // MARK: - Subviews

    public let tableView = UITableView()
    public let inputBar = OpenAPPInputBar()
    let voiceInputOverlayView = OpenAPPVoiceInputOverlayView()

    // MARK: - Data

    var chatMessages: [ChatMessage] = []
    var currentStreamTask: Task<Void, Never>?
    var observedKeyboardHeight: CGFloat = 0
    var hasLaidOutInputBar = false
    var isDraggingExpandedInputBar = false
    var isDraggingCollapsedInputBar = false
    var storedExpandedInputBarWidth: CGFloat?
    var storedCollapsedInputBarPlacement: CGPoint?
    var expandedResizeStableWidth: CGFloat?
    var expandedResizeStableStartTime: TimeInterval?
    var activeVoiceInput: ActiveVoiceInput?
    var voiceRecognitionTask: Task<Void, Never>?
    let voiceRecognitionManager = OpenAPPVoiceRecognitionManager.shared
    lazy var voiceRecognitionHapticGenerator = makeVoiceRecognitionHapticGenerator()

    struct ActiveVoiceInput {
        /// 手指状态：当前手指在 OpenAPPViewController 坐标系中的位置。
        var fingerLocation: CGPoint

        /// 识别状态：语音识别在 UI 上呈现为未开始、加载中或录音中。
        var recognitionState: OpenAPPVoiceRecognitionVisualState = .loading

        /// 抬起行为：当前手指位置对应的松手后动作。
        var releaseAction: OpenAPPVoiceInputReleaseAction = .send

        /// 识别文本：语音识别管理器实时返回的文本内容。
        var transcriptText = ""

        var showsTranscriptCursor: Bool {
            !transcriptText.isEmpty
        }
    }

    var isVoiceInputActive: Bool {
        activeVoiceInput != nil
    }

    var effectiveKeyboardHeight: CGFloat {
        shouldInputBarAvoidKeyboard ? observedKeyboardHeight : 0
    }

    var shouldInputBarAvoidKeyboard: Bool {
        inputBar.inputSource == .keyboard && inputBar.textField.isFirstResponder
    }

    /// 宽屏判定阈值：OpenAPPViewController 宽度大于该值时，按宽屏 inputBar 策略处理。
    static let inputBarWideLayoutWidth: CGFloat = 440

    /// 宽屏默认展开宽度上限：用户未手动调整宽度前，展开态 inputBar 默认最大不超过该值。
    static let inputBarWideDefaultMaxWidth: CGFloat = 600

    /// inputBar 与容器左右安全区域之间的水平间距，由 OpenAPPViewController 外部布局统一控制。
    static let inputBarHorizontalInset: CGFloat = 12

    /// inputBar 避让键盘时与键盘顶部保留的间距，当前为 0 表示紧贴键盘。
    static let inputBarKeyboardSpacing: CGFloat = 0

    /// 慢速手势阈值：速度绝对值不超过该值时，按“低速/近静止”策略判断最终状态。
    static let inputBarSlowVelocityThreshold: CGFloat = 50

    /// 快速手势阈值：速度绝对值达到该值时，直接按手势方向决定展开/收起或吸附方向。
    static let inputBarFastVelocityThreshold: CGFloat = 650

    /// 中速手势投影系数：用当前速度预估阻尼落点，再根据落点决定最终状态。
    static let inputBarProjectionFactor: CGFloat = 0.18

    /// 宽屏展开 resize 的稳定停留时长：手指在某个宽度附近停留超过该时长后，可将该宽度记为用户偏好。
    static let expandedResizeHoldDuration: TimeInterval = 0

    /// 宽屏展开 resize 的宽度稳定阈值：宽度变化不超过该值时，认为仍停留在同一个目标宽度附近。
    static let expandedResizeWidthStabilityThreshold: CGFloat = 4

    /// UserDefaults key：保存宽屏下用户手动调整后的展开态 inputBar 宽度。
    static let expandedWidthDefaultsKey = "com.openapp.ui.inputBar.wideExpandedWidth"

    /// UserDefaults key：保存收起态 inputBar 位置，格式为 x,y，支持正负偏移以适配安全区域和尺寸变化。
    static let collapsedPlacementDefaultsKey = "com.openapp.ui.inputBar.collapsedPlacementXY"

    // MARK: - Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        loadPersistedInputBarLayout()
        setupTableView()
        setupInputBar()
        setupVoiceInputOverlay()
        setupKeyboardObservers()

        reloadFromSession()
        bindUIState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        currentSession?.uiState.onChange = nil
        voiceRecognitionTask?.cancel()
    }

    // MARK: - Manual Frame Layout

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutInputBar(reason: .layout)
        voiceInputOverlayView.frame = view.bounds
        view.bringSubviewToFront(voiceInputOverlayView)
    }
}

#endif
