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
}
#endif
