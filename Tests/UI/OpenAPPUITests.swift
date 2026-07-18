#if canImport(UIKit)
import XCTest
@testable import OpenAPP

final class OpenAPPUITests: XCTestCase {

    func testChatMessageCreation() {
        let msg = ChatMessage(role: .user, text: "Hello")
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.text, "Hello")
        XCTAssertEqual(msg.status, .complete)
        XCTAssertNotNil(msg.id)
        XCTAssertNotNil(msg.timestamp)
    }

    func testChatMessageStreamingStatus() {
        let msg = ChatMessage(role: .assistant, text: "", status: .streaming)
        XCTAssertEqual(msg.status, .streaming)
        XCTAssertEqual(msg.role, .assistant)
    }

    func testInputBarInputAreaAlphaFadesWhileCollapsingBelowMinimumExpandedWidth() {
        let inputBar = OpenAPPInputBar()

        inputBar.frame = CGRect(x: 0, y: 0, width: 240, height: 56)
        inputBar.layoutIfNeeded()
        XCTAssertEqual(inputBar.inputAreaContainer.alpha, 1, accuracy: 0.001)

        inputBar.frame = CGRect(x: 0, y: 0, width: 200, height: 56)
        inputBar.layoutIfNeeded()
        XCTAssertEqual(inputBar.inputAreaContainer.alpha, 0.5, accuracy: 0.001)

        inputBar.frame = CGRect(x: 0, y: 0, width: 160, height: 56)
        inputBar.layoutIfNeeded()
        XCTAssertEqual(inputBar.inputAreaContainer.alpha, 0, accuracy: 0.001)
        XCTAssertTrue(inputBar.textField.isUserInteractionEnabled)

        inputBar.frame = CGRect(x: 0, y: 0, width: OpenAPPInputBar.collapsedMinWidth, height: 56)
        inputBar.layoutIfNeeded()
        XCTAssertFalse(inputBar.textField.isUserInteractionEnabled)
    }
}
#endif
