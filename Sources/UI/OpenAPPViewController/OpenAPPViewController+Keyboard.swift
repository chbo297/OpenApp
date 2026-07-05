//
//  OpenAPPViewController+Keyboard.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

// MARK: - Keyboard

extension OpenAPPViewController {
    func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
    }

    @objc func keyboardWillChangeFrame(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
        else { return }

        let kbInView = view.convert(endFrame, from: nil)
        let newKeyboardH = max(0, view.bounds.intersection(kbInView).height)

        let oldEffectiveKeyboardHeight = effectiveKeyboardHeight
        observedKeyboardHeight = newKeyboardH
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
