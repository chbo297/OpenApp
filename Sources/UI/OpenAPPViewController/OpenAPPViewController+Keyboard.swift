//
//  OpenAPPViewController+Keyboard.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

// MARK: - Keyboard

extension OpenAPPViewController {
    func setupKeyboardObservers() {
        let observer = OpenAPPKeyboardObserver(referenceView: view)
        observer.onChange = { [weak self] height, duration in
            self?.handleKeyboardHeightChange(height: height, duration: duration)
        }
        keyboardObserver = observer
    }

    func handleKeyboardHeightChange(height: CGFloat, duration: TimeInterval) {
        let oldEffectiveKeyboardHeight = effectiveKeyboardHeight
        observedKeyboardHeight = height
        let newEffectiveKeyboardHeight = effectiveKeyboardHeight

        // 对话流面板的列表 inset 跟随任何键盘高度变化（面板 frame 本身不避让）。
        UIView.animate(withDuration: max(duration, 0.01)) {
            self.updateChatPanelListInsets()
        }

        guard abs(oldEffectiveKeyboardHeight - newEffectiveKeyboardHeight) > 0.5 else {
            return
        }

        UIView.animate(withDuration: duration) {
            self.layoutInputBar(reason: .keyboard)
        }

        scrollToBottom(animated: true)
    }
}

#endif
