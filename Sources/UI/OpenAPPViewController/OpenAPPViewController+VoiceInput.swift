//
//  OpenAPPViewController+VoiceInput.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

// MARK: - Voice Input

extension OpenAPPViewController {
    /// 初始化语音输入图层：图层常驻在 OpenAPPViewController 上，默认隐藏，手势开始时展示。
    func setupVoiceInputOverlay() {
        voiceInputOverlayView.frame = view.bounds
        voiceInputOverlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(voiceInputOverlayView)
    }

    /// 外部或识别管理器更新实时识别文本时调用：只改文字，不改变手指当前选择的抬起行为。
    public func updateVoiceInputTranscript(_ text: String) {
        guard var input = activeVoiceInput else { return }
        input.transcriptText = text
        activeVoiceInput = input
        renderVoiceInputOverlay()
    }

    /// 语音输入手势总入口：inputBar 只透传手势，OpenAPPViewController 在这里按 began/changed/ended/cancelled 分发生命周期。
    func handleVoiceInputGesture(
        _ gestureRecognizer: UILongPressGestureRecognizer,
        source: OpenAPPInputBarVoiceInputSource,
        state: UIGestureRecognizer.State
    ) {
        let location = gestureRecognizer.location(in: view)

        switch state {
        case .began:
            beginVoiceInput(source: source, startLocation: location)
        case .changed:
            updateVoiceInput(location: location)
        case .ended:
            endVoiceInput(location: location)
        case .cancelled, .failed:
            cancelVoiceInput(location: location)
        case .possible:
            break
        @unknown default:
            break
        }
    }

    /// 手势开始：创建本次语音输入状态、启动识别、展示图层，并立刻按起点计算一次松手行为。
    func beginVoiceInput(source: OpenAPPInputBarVoiceInputSource, startLocation: CGPoint) {
        // 手指状态：刚按下输入区，创建本次语音输入上下文，默认松手行为是发送。
        activeVoiceInput = ActiveVoiceInput(fingerLocation: startLocation)

        // 识别状态：立刻把录音诉求交给语音管理器，UI 层不再做时间等待或防抖。
        startVoiceRecognition()

        // UI状态：展示语音输入图层，展示完成后立刻按当前手指位置刷新抬起行为。
        voiceInputOverlayView.show(startLocation: startLocation, animated: false)
        updateVoiceInputReleaseAction(for: startLocation)

        // 交互反馈：用户触发语音输入时立即震动一次。
        performVoiceInputBeginHaptic(for: source)
    }

    /// 手势移动：每次移动都按当前位置重新判断“手指如果此刻抬起应该执行 send/cancel/edit 哪个行为”。
    func updateVoiceInput(location: CGPoint) {
        // 手指状态：移动过程中持续按当前位置计算松手行为。
        updateVoiceInputReleaseAction(for: location)
    }

    /// 手势抬起：先用最终位置刷新松手行为，再根据最终行为执行发送、取消或编辑。
    func endVoiceInput(location: CGPoint) {
        guard isVoiceInputActive else { return }

        // 手指状态：抬起前先用最终位置刷新一次松手行为，保证最终动作和最后落点一致。
        updateVoiceInputReleaseAction(for: location)

        let finalReleaseAction = activeVoiceInput?.releaseAction ?? .cancel
        switch finalReleaseAction {
        case .send:
            finishVoiceInputSend()
        case .cancel:
            finishVoiceInputCancel()
        case .edit:
            finishVoiceInputEdit()
        }
    }

    /// 手势取消/失败：刷新当前位置用于 UI 一致性，但最终不发送，统一取消本次语音输入。
    func cancelVoiceInput(location: CGPoint) {
        guard isVoiceInputActive else { return }

        // 手指状态：系统取消或手势失败时也先刷新当前位置，便于 UI 与调试状态保持一致。
        updateVoiceInputReleaseAction(for: location)

        // 程序状态：系统取消/失败不是用户明确发送，统一按取消收尾。
        finishVoiceInputCancel()
    }

    /// 手势位置判定核心：这里把当前手指位置转换为抬起行为。
    ///
    /// 具体判断在 `voiceInputOverlayView.releaseAction(for:)` 中完成，顺序是：
    /// 1. bottomPanel 的 pointInside 命中则为 send
    /// 2. 取消按钮区域命中则为 cancel
    /// 3. 编辑按钮区域命中则为 edit
    /// 4. 都未命中时默认 send
    func updateVoiceInputReleaseAction(for location: CGPoint) {
        guard var input = activeVoiceInput else { return }
        input.fingerLocation = location
        input.releaseAction = voiceInputOverlayView.releaseAction(for: location)
        activeVoiceInput = input
        renderVoiceInputOverlay()
    }

    /// 识别状态更新：只更新 none/loading/recording，不改变手指当前选择的抬起行为。
    func updateVoiceRecognitionVisualState(_ recognitionState: OpenAPPVoiceRecognitionVisualState) {
        guard var input = activeVoiceInput else { return }
        input.recognitionState = recognitionState
        activeVoiceInput = input
        renderVoiceInputOverlay()
    }

    /// 录音中识别文本更新：录音事件到来时同时进入 recording 状态并刷新实时文字，避免重复渲染。
    func updateVoiceRecognitionRecordingText(_ text: String) {
        guard var input = activeVoiceInput else { return }
        input.recognitionState = .recording
        input.transcriptText = text
        activeVoiceInput = input
        renderVoiceInputOverlay()
    }

    /// 渲染语音输入图层：把识别状态、抬起行为、手指位置和实时文本统一同步给 overlay。
    func renderVoiceInputOverlay() {
        guard let input = activeVoiceInput else { return }
        voiceInputOverlayView.update(
            recognitionState: input.recognitionState,
            releaseAction: input.releaseAction,
            fingerLocation: input.fingerLocation,
            transcriptText: input.transcriptText,
            showsTranscriptCursor: input.showsTranscriptCursor
        )
    }

    /// 最终行为：松手发送。震动后停止录音，并隐藏语音输入图层。
    func finishVoiceInputSend() {
        performVoiceRecognitionHaptic(reason: "stop-send")
        stopVoiceRecognition(reason: .userStopped)
        resetVoiceInputOverlay(animated: true)
    }

    /// 最终行为：松手取消。震动后取消录音诉求，并隐藏语音输入图层。
    func finishVoiceInputCancel() {
        performVoiceRecognitionHaptic(reason: "stop-cancel")
        stopVoiceRecognition(reason: .cancelled)
        resetVoiceInputOverlay(animated: true)
    }

    /// 最终行为：松手编辑。停止录音，把实时识别文本写入 textField，并切回键盘输入。
    func finishVoiceInputEdit() {
        let transcript = activeVoiceInput?.transcriptText ?? ""
        performVoiceRecognitionHaptic(reason: "stop-edit")
        stopVoiceRecognition(reason: .userStopped)
        resetVoiceInputOverlay(animated: true)
        inputBar.setInputSource(.keyboard, animated: true)
        if !transcript.isEmpty {
            inputBar.text = inputBar.text.isEmpty ? transcript : inputBar.text + transcript
        }
        inputBar.textField.becomeFirstResponder()
    }

    /// 重置语音输入 UI：清空本次 active 状态并隐藏 overlay。
    func resetVoiceInputOverlay(animated: Bool) {
        activeVoiceInput = nil
        voiceInputOverlayView.hide(animated: animated)
    }

    /// 启动语音识别：创建语音管理器事件流，并在主线程消费 loading/recording/ended 事件。
    func startVoiceRecognition() {
        voiceRecognitionTask?.cancel()
        let events = voiceRecognitionManager.startRecording()
        voiceRecognitionTask = Task { @MainActor [weak self] in
            for await event in events {
                self?.handleVoiceRecognitionEvent(event)
            }
        }
    }

    /// 处理语音管理器事件：识别状态只影响 loading/recording/none，不能覆盖手指当前选择的 send/cancel/edit。
    func handleVoiceRecognitionEvent(_ event: OpenAPPVoiceRecognitionEvent) {
        switch event {
        case .loading:
            guard isVoiceInputActive else {
                return
            }
            updateVoiceRecognitionVisualState(.loading)
        case .recording(let context):
            guard isVoiceInputActive else {
                return
            }
            updateVoiceRecognitionRecordingText(context.combinedText)
        case .ended:
            voiceRecognitionTask = nil
            guard isVoiceInputActive else {
                return
            }
            updateVoiceRecognitionVisualState(.none)
            resetVoiceInputOverlay(animated: true)
        }
    }

    /// 停止语音识别：把结束原因交给语音管理器，由音频队列异步清理录音资源。
    func stopVoiceRecognition(reason: OpenAPPVoiceRecognitionEndReason) {
        voiceRecognitionManager.requestStopRecording(reason: reason)
    }

    /// 执行语音输入震动：开始语音、发送、取消、编辑都会走这里，保持震动策略集中。
    func performVoiceRecognitionHaptic(reason: String) {
        voiceRecognitionHapticGenerator.prepare()
        voiceRecognitionHapticGenerator.impactOccurred(intensity: 1)
    }

    /// 根据触发来源执行开始震动：文字输入长按和语音输入区按下都视为用户开始语音输入。
    func performVoiceInputBeginHaptic(for source: OpenAPPInputBarVoiceInputSource) {
        switch source {
        case .textInputLongPress:
            performVoiceRecognitionHaptic(reason: "start-text-input-long-press")
        case .voiceInputArea:
            performVoiceRecognitionHaptic(reason: "start-voice-input-touch")
        }
    }

    /// 创建语音输入震动发生器：新系统优先绑定 view，旧系统使用传统 heavy 样式。
    func makeVoiceRecognitionHapticGenerator() -> UIImpactFeedbackGenerator {
        if #available(iOS 17.5, *) {
            return UIImpactFeedbackGenerator(style: .heavy, view: self.view)
        } else {
            return UIImpactFeedbackGenerator(style: .heavy)
        }
    }
}

#endif
