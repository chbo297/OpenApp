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
