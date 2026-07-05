//
//  OpenAPPVoiceInputOverlayView.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

final class OpenAPPVoiceInputOverlayView: UIView {

    private static let bubbleGreen = UIColor(red: 0.56, green: 0.94, blue: 0.40, alpha: 1)
    private static let bubbleRed = UIColor(red: 1.00, green: 0.30, blue: 0.33, alpha: 1)
    private static let waveformGreen = UIColor(red: 0.24, green: 0.55, blue: 0.20, alpha: 0.55)
    private static let waveformRed = UIColor(red: 0.42, green: 0.05, blue: 0.07, alpha: 0.42)
    private static let cursorGreen = UIColor(red: 0.14, green: 0.78, blue: 0.50, alpha: 1)
    private static let backgroundFadeDuration: TimeInterval = 0.2
    private static let bottomPanelEntranceDuration: TimeInterval = 0.06
    private static let bottomPanelTopRevealHeight: CGFloat = 40
    private static let isHitTestingDebugLoggingEnabled = false

    private let backgroundView = UIView()
    private let bubbleView = OpenAPPVoiceBubbleView()
    private let waveformView = OpenAPPVoiceWaveformView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let transcriptLabel = UILabel()
    private let bottomPanelView = OpenAPPVoiceBottomPanelView()
    private let cancelZoneView = OpenAPPVoiceActionZoneView(side: .left)
    private let editZoneView = OpenAPPVoiceActionZoneView(side: .right)
    private let cancelLabel = UILabel()
    private let editLabel = UILabel()
    private let cancelHintLabel = UILabel()
    private let editHintLabel = UILabel()

    private var currentRecognitionState: OpenAPPVoiceRecognitionVisualState = .none
    private var currentReleaseAction: OpenAPPVoiceInputReleaseAction = .send
    private var currentFingerLocation: CGPoint = .zero
    private var transcriptText = ""
    private var showsTranscriptCursor = false
    private var cachedGeometryBounds: CGRect = .null
    private var cachedGeometrySafeAreaInsets: UIEdgeInsets = .zero
    private var cachedBottomPanelFrame: CGRect = .zero
    private var cachedActionZoneFrames: (cancel: CGRect, edit: CGRect) = (.zero, .zero)
    private var cachedTranscriptMeasurementText = ""
    private var cachedTranscriptMeasurementWidth: CGFloat = -1
    private var cachedTranscriptMeasurementHeight: CGFloat = 0
    private var visibilityAnimationID = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func show(startLocation: CGPoint, animated: Bool) {
        let shouldResetBackgroundAlpha = isHidden || backgroundView.alpha <= 0.01
        currentFingerLocation = startLocation
        activityIndicator.startAnimating()
        setNeedsLayout()
        layoutIfNeeded()
        setOverlayVisible(true, animated: animated)
        animateBackgroundVisibility(true, animated: animated, resetAlpha: shouldResetBackgroundAlpha)
        animateBottomPanelEntrance()
    }

    func update(
        recognitionState: OpenAPPVoiceRecognitionVisualState,
        releaseAction: OpenAPPVoiceInputReleaseAction,
        fingerLocation: CGPoint,
        transcriptText: String,
        showsTranscriptCursor: Bool
    ) {
        let recognitionChanged = currentRecognitionState != recognitionState
        let releaseActionChanged = currentReleaseAction != releaseAction
        let transcriptChanged = self.transcriptText != transcriptText
        let cursorChanged = self.showsTranscriptCursor != showsTranscriptCursor
        let fingerLocationChanged = !currentFingerLocation.isApproximatelyEqual(to: fingerLocation)
        guard recognitionChanged
            || releaseActionChanged
            || transcriptChanged
            || cursorChanged
            || fingerLocationChanged else {
            return
        }

        currentRecognitionState = recognitionState
        currentReleaseAction = releaseAction
        currentFingerLocation = fingerLocation
        self.transcriptText = transcriptText
        self.showsTranscriptCursor = showsTranscriptCursor
        let isLoading = recognitionState == .loading && transcriptText.isEmpty
        updateActivityIndicator(isLoading: isLoading)
        if transcriptChanged || cursorChanged {
            updateTranscriptText()
            invalidateTranscriptMeasurementCache()
        }
        if recognitionChanged || releaseActionChanged || transcriptChanged || cursorChanged {
            setNeedsLayout()
        }
    }

    func hide(animated: Bool) {
        let complete = { [weak self] in
            guard let self else { return }
            self.isHidden = true
            self.alpha = 1
            self.activityIndicator.stopAnimating()
            self.transcriptText = ""
            self.showsTranscriptCursor = false
            self.currentRecognitionState = .none
            self.currentReleaseAction = .send
            self.invalidateTranscriptMeasurementCache()
            self.updateTranscriptText()
        }
        setOverlayVisible(false, animated: animated, completion: complete)
    }

    private func setOverlayVisible(
        _ visible: Bool,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        visibilityAnimationID += 1
        let animationID = visibilityAnimationID

        if visible {
            isHidden = false
            alpha = 1
            completion?()
            return
        }

        let finish = { [weak self] in
            guard let self, self.visibilityAnimationID == animationID else { return }
            self.isHidden = true
            completion?()
        }

        guard animated else {
            backgroundView.alpha = 0
            finish()
            return
        }

        animateBackgroundVisibility(false, animated: true, resetAlpha: false, completion: finish)
    }

    private func animateBottomPanelEntrance() {
        bottomPanelView.layer.removeAnimation(forKey: "openapp.voice.bottomPanelEntrance")
        let translationAnimation = CABasicAnimation(keyPath: "transform.translation.y")
        translationAnimation.fromValue = Self.bottomPanelTopRevealHeight
        translationAnimation.toValue = 0
        translationAnimation.isAdditive = true

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0
        opacityAnimation.toValue = 1

        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [translationAnimation, opacityAnimation]
        animationGroup.duration = Self.bottomPanelEntranceDuration
        animationGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
        bottomPanelView.layer.add(animationGroup, forKey: "openapp.voice.bottomPanelEntrance")
    }

    private func animateBackgroundVisibility(
        _ visible: Bool,
        animated: Bool,
        resetAlpha: Bool,
        completion: (() -> Void)? = nil
    ) {
        if resetAlpha {
            backgroundView.alpha = visible ? 0 : 1
        }

        let apply = {
            self.backgroundView.alpha = visible ? 1 : 0
        }

        guard animated else {
            apply()
            completion?()
            return
        }

        UIView.animate(
            withDuration: Self.backgroundFadeDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
            animations: apply,
            completion: { _ in completion?() }
        )
    }

    func releaseAction(for fingerLocation: CGPoint) -> OpenAPPVoiceInputReleaseAction {
        refreshGeometryCacheIfNeeded()
        setFrameIfNeeded(cachedBottomPanelFrame, for: bottomPanelView)

        // 手指命中：先判断底部发送面板，bottom 和上方按钮区域重叠时优先发送。
        if isFingerInsideBottomPanel(fingerLocation) {
            return .send
        }

        // 手指命中：再判断左侧取消区域。
        let zones = cachedActionZoneFrames
        if zones.cancel.contains(fingerLocation) {
            return .cancel
        }

        // 手指命中：最后判断右侧编辑区域。
        if zones.edit.contains(fingerLocation) {
            return .edit
        }

        // 手指命中：未进入取消/编辑时，松手行为仍按发送处理。
        return .send
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setFrameIfNeeded(bounds, for: backgroundView)
        refreshGeometryCacheIfNeeded()
        layoutActionZones()
        layoutBubble()
    }

    private func setup() {
        isHidden = true
        alpha = 0
        isUserInteractionEnabled = false
        backgroundColor = .clear

        backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        backgroundView.alpha = 0
        addSubview(backgroundView)

        bubbleView.backgroundColor = .clear
        addSubview(bubbleView)

        waveformView.backgroundColor = .clear
        bubbleView.addSubview(waveformView)

        activityIndicator.color = Self.waveformGreen
        bubbleView.addSubview(activityIndicator)

        transcriptLabel.numberOfLines = 0
        transcriptLabel.lineBreakMode = .byWordWrapping
        transcriptLabel.font = .systemFont(ofSize: 30, weight: .medium)
        bubbleView.addSubview(transcriptLabel)

        bottomPanelView.backgroundColor = .clear
        addSubview(bottomPanelView)

        [cancelZoneView, editZoneView].forEach {
            $0.backgroundColor = .clear
            addSubview($0)
        }

        configureActionLabel(cancelLabel, text: "取消")
        configureActionLabel(editLabel, text: "编辑")
        configureHintLabel(cancelHintLabel)
        configureHintLabel(editHintLabel)

        cancelZoneView.addSubview(cancelLabel)
        editZoneView.addSubview(editLabel)
        addSubview(cancelHintLabel)
        addSubview(editHintLabel)
        updateTranscriptText()
    }

    private func configureActionLabel(_ label: UILabel, text: String) {
        label.text = text
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 25, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.88)
    }

    private func configureHintLabel(_ label: UILabel) {
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.62)
        label.alpha = 0
    }

    private func layoutActionZones() {
        refreshGeometryCacheIfNeeded()
        let zones = cachedActionZoneFrames
        let panelFrame = cachedBottomPanelFrame
        setFrameIfNeeded(panelFrame, for: bottomPanelView)
        setFrameIfNeeded(zones.cancel, for: cancelZoneView)
        setFrameIfNeeded(zones.edit, for: editZoneView)

        cancelLabel.transform = .identity
        editLabel.transform = .identity
        cancelLabel.bounds = CGRect(x: 0, y: 0, width: min(180, zones.cancel.width * 0.68), height: 40)
        cancelLabel.center = CGPoint(x: zones.cancel.width * 0.48, y: zones.cancel.height * 0.58)
        cancelLabel.transform = CGAffineTransform(rotationAngle: -0.16)
        editLabel.bounds = CGRect(x: 0, y: 0, width: min(260, zones.edit.width * 0.72), height: 44)
        editLabel.center = CGPoint(x: zones.edit.width * 0.48, y: zones.edit.height * 0.58)
        editLabel.transform = CGAffineTransform(rotationAngle: 0.15)

        cancelHintLabel.frame = CGRect(
            x: max(0, zones.cancel.minX),
            y: zones.cancel.minY - 42,
            width: min(bounds.width * 0.48, zones.cancel.width),
            height: 30
        )
        editHintLabel.frame = CGRect(
            x: min(bounds.width * 0.55, zones.edit.minX),
            y: zones.edit.minY - 42,
            width: min(bounds.width * 0.45, zones.edit.width),
            height: 30
        )

        let cancelSelected = currentReleaseAction == .cancel
        let editSelected = currentReleaseAction == .edit
        bottomPanelView.setSelected(currentReleaseAction == .send)
        cancelZoneView.fillColor = cancelSelected
            ? UIColor.white.withAlphaComponent(0.84)
            : UIColor.white.withAlphaComponent(0.13)
        editZoneView.fillColor = editSelected
            ? UIColor.white.withAlphaComponent(0.84)
            : UIColor.white.withAlphaComponent(0.13)
        cancelLabel.textColor = cancelSelected ? .black : UIColor.white.withAlphaComponent(0.88)
        editLabel.textColor = editSelected ? .black : UIColor.white.withAlphaComponent(0.88)
        cancelHintLabel.text = cancelSelected ? "松手 取消" : nil
        editHintLabel.text = editSelected ? "松手 编辑文字" : nil
        cancelHintLabel.alpha = cancelSelected ? 1 : 0
        editHintLabel.alpha = editSelected ? 1 : 0
    }

    private func isFingerInsideBottomPanel(_ fingerLocation: CGPoint) -> Bool {
        let bottomPoint = bottomPanelView.convert(fingerLocation, from: self)
        if Self.isHitTestingDebugLoggingEnabled {
            print("[OpenAPPVoiceInputOverlay] bottomPoint=\(bottomPoint)")
        }
        return bottomPanelView.point(inside: bottomPoint, with: nil)
    }

    private func layoutBubble() {
        let hasTranscript = !transcriptText.isEmpty && currentReleaseAction != .cancel
        let isLoading = currentRecognitionState == .loading && !hasTranscript
        let bubbleFrame = preferredBubbleFrame(hasTranscript: hasTranscript)
        let didChangeBubbleSize = setFrameIfNeeded(bubbleFrame, for: bubbleView)
        bubbleView.fillColor = currentReleaseAction == .cancel ? Self.bubbleRed : Self.bubbleGreen
        bubbleView.cornerRadius = hasTranscript ? 18 : 16
        bubbleView.tailXRatio = hasTranscript || currentReleaseAction == .edit ? 0.84 : 0.5
        if didChangeBubbleSize {
            bubbleView.setNeedsDisplay()
        }

        transcriptLabel.isHidden = !hasTranscript
        activityIndicator.isHidden = !isLoading
        waveformView.isHidden = isLoading
        waveformView.barColor = currentReleaseAction == .cancel ? Self.waveformRed : Self.waveformGreen

        if hasTranscript {
            let textInset = UIEdgeInsets(top: 24, left: 24, bottom: 44, right: 24)
            setFrameIfNeeded(bubbleView.bounds.inset(by: textInset), for: transcriptLabel)
            let didChangeWaveformSize = setFrameIfNeeded(CGRect(
                x: bubbleView.bounds.maxX - 92,
                y: bubbleView.bounds.maxY - 58,
                width: 64,
                height: 30
            ), for: waveformView)
            if didChangeWaveformSize {
                waveformView.setNeedsDisplay()
            }
            activityIndicator.center = CGPoint(x: bubbleView.bounds.midX, y: bubbleView.bounds.midY)
        } else {
            setFrameIfNeeded(.zero, for: transcriptLabel)
            let waveSize = CGSize(width: 78, height: 34)
            let didChangeWaveformSize = setFrameIfNeeded(CGRect(
                x: (bubbleView.bounds.width - waveSize.width) / 2,
                y: (bubbleView.bounds.height - 10 - waveSize.height) / 2,
                width: waveSize.width,
                height: waveSize.height
            ), for: waveformView)
            if didChangeWaveformSize {
                waveformView.setNeedsDisplay()
            }
            activityIndicator.center = CGPoint(x: bubbleView.bounds.midX, y: bubbleView.bounds.midY - 5)
        }
    }

    private func preferredBubbleFrame(hasTranscript: Bool) -> CGRect {
        refreshGeometryCacheIfNeeded()
        let zones = cachedActionZoneFrames
        let maxBubbleBottom = zones.cancel.minY - 92
        let safeTop = safeAreaInsets.top

        if hasTranscript {
            let maxWidth = max(0, min(bounds.width - 48, 620))
            let labelWidth = max(0, maxWidth - 48)
            let textHeight = measuredTranscriptHeight(for: labelWidth)
            let height = Self.clamp(textHeight + 84, 140, 260)
            let y = Self.clamp(maxBubbleBottom - height, safeTop + 96, max(0, maxBubbleBottom - height))
            return CGRect(
                x: (bounds.width - maxWidth) / 2,
                y: y,
                width: maxWidth,
                height: height
            )
        }

        let width: CGFloat
        let x: CGFloat
        switch currentReleaseAction {
        case .cancel:
            width = max(0, min(188, bounds.width - 64))
            x = 32
        case .edit:
            width = max(0, min(bounds.width - 48, 620))
            x = (bounds.width - width) / 2
        case .send:
            width = max(0, min(260, bounds.width - 64))
            x = (bounds.width - width) / 2
        }
        let height: CGFloat = 118
        let y = Self.clamp(maxBubbleBottom - height, safeTop + 120, max(0, maxBubbleBottom - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func updateTranscriptText() {
        let text = showsTranscriptCursor && !transcriptText.isEmpty
            ? transcriptText + "|"
            : transcriptText
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .foregroundColor: UIColor.black,
                .font: UIFont.systemFont(ofSize: 30, weight: .medium)
            ]
        )
        if showsTranscriptCursor, !transcriptText.isEmpty {
            let cursorRange = NSRange(location: attributed.length - 1, length: 1)
            attributed.addAttributes(
                [
                    .foregroundColor: Self.cursorGreen,
                    .font: UIFont.systemFont(ofSize: 32, weight: .regular)
                ],
                range: cursorRange
            )
        }
        transcriptLabel.attributedText = attributed
    }

    @discardableResult
    private func refreshGeometryCacheIfNeeded() -> Bool {
        guard !cachedGeometryBounds.isApproximatelyEqual(to: bounds)
            || !cachedGeometrySafeAreaInsets.isApproximatelyEqual(to: safeAreaInsets) else {
            return false
        }

        cachedGeometryBounds = bounds
        cachedGeometrySafeAreaInsets = safeAreaInsets
        cachedBottomPanelFrame = makeBottomPanelFrame()
        cachedActionZoneFrames = makeActionZoneFrames(bottomPanelFrame: cachedBottomPanelFrame)
        return true
    }

    private func makeActionZoneFrames(bottomPanelFrame panelFrame: CGRect) -> (cancel: CGRect, edit: CGRect) {
        let zoneY = panelFrame.minY - 98
        let zoneHeight: CGFloat = 136
        let cancel = CGRect(
            x: -68,
            y: zoneY,
            width: bounds.width * 0.64,
            height: zoneHeight
        )
        let edit = CGRect(
            x: bounds.width * 0.49,
            y: zoneY,
            width: bounds.width * 0.68,
            height: zoneHeight
        )
        return (cancel, edit)
    }

    private func makeBottomPanelFrame() -> CGRect {
        let safeBottom = safeAreaInsets.bottom
        let panelHeight = Self.bottomPanelTopRevealHeight + OpenAPPInputBar.barHeight + safeBottom
        return CGRect(
            x: 0,
            y: max(0, bounds.height - panelHeight),
            width: bounds.width,
            height: panelHeight
        )
    }

    private func measuredTranscriptHeight(for width: CGFloat) -> CGFloat {
        let text = transcriptLabel.attributedText?.string ?? ""
        guard cachedTranscriptMeasurementText != text
            || abs(cachedTranscriptMeasurementWidth - width) > 0.5 else {
            return cachedTranscriptMeasurementHeight
        }

        let height = transcriptLabel.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        ).height
        cachedTranscriptMeasurementText = text
        cachedTranscriptMeasurementWidth = width
        cachedTranscriptMeasurementHeight = height
        return height
    }

    private func invalidateTranscriptMeasurementCache() {
        cachedTranscriptMeasurementText = ""
        cachedTranscriptMeasurementWidth = -1
        cachedTranscriptMeasurementHeight = 0
    }

    private func updateActivityIndicator(isLoading: Bool) {
        let shouldHide = !isLoading
        if activityIndicator.isHidden != shouldHide {
            activityIndicator.isHidden = shouldHide
        }

        if isLoading {
            if !activityIndicator.isAnimating {
                activityIndicator.startAnimating()
            }
        } else if activityIndicator.isAnimating {
            activityIndicator.stopAnimating()
        }
    }

    @discardableResult
    private func setFrameIfNeeded(_ frame: CGRect, for view: UIView) -> Bool {
        let oldSize = view.bounds.size
        let targetCenter = CGPoint(x: frame.midX, y: frame.midY)
        guard !oldSize.isApproximatelyEqual(to: frame.size)
            || !view.center.isApproximatelyEqual(to: targetCenter) else {
            return false
        }

        view.bounds = CGRect(origin: .zero, size: frame.size)
        view.center = targetCenter
        return !oldSize.isApproximatelyEqual(to: view.bounds.size)
    }

    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        guard hi >= lo else { return lo }
        return min(hi, max(lo, v))
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect) -> Bool {
        abs(minX - other.minX) <= 0.5
            && abs(minY - other.minY) <= 0.5
            && abs(width - other.width) <= 0.5
            && abs(height - other.height) <= 0.5
    }
}

private extension CGSize {
    func isApproximatelyEqual(to other: CGSize) -> Bool {
        abs(width - other.width) <= 0.5
            && abs(height - other.height) <= 0.5
    }
}

private extension CGPoint {
    func isApproximatelyEqual(to other: CGPoint) -> Bool {
        abs(x - other.x) <= 0.5
            && abs(y - other.y) <= 0.5
    }
}

private extension UIEdgeInsets {
    func isApproximatelyEqual(to other: UIEdgeInsets) -> Bool {
        abs(top - other.top) <= 0.5
            && abs(left - other.left) <= 0.5
            && abs(bottom - other.bottom) <= 0.5
            && abs(right - other.right) <= 0.5
    }
}

#endif
