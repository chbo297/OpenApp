#if canImport(UIKit)
import XCTest
@testable import OpenAPP

/// ChatPanel 业务几何与 BODragScroll 接线测试；运动物理由 BODragScroll 自身测试覆盖。
@MainActor
final class OpenAPPChatPanelGeometryTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
    private let safeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    private let inputBarExpandedFrame = CGRect(x: 12, y: 762, width: 369, height: 56)

    func testViewControllerUsesRealSessionByDefault() {
        XCTAssertFalse(OpenAPPViewController().usesMockChatResponder)
    }

    func testRegularGeometryProducesExpectedPanelAndDetents() throws {
        let geometry = try XCTUnwrap(makeGeometry())

        XCTAssertEqual(geometry.panelSize.width, 369 + 16, accuracy: 0.5)
        XCTAssertEqual(geometry.fullHeight, 852 - 59, accuracy: 0.5)
        XCTAssertEqual(
            geometry.peekHeight,
            34 + OpenAPPInputBar.barHeight + OpenAPPChatPanelGeometry.peekVisibleHeight,
            accuracy: 0.5
        )
        XCTAssertEqual(geometry.halfHeight, geometry.fullHeight * 0.5, accuracy: 0.5)
        XCTAssertEqual(
            geometry.detentHeights,
            [geometry.peekHeight, geometry.halfHeight, geometry.fullHeight]
        )
    }

    func testPanelWidthNeverExceedsViewport() throws {
        let geometry = try XCTUnwrap(
            OpenAPPChatPanelGeometry(
                bounds: bounds,
                safeAreaInsets: safeAreaInsets,
                inputBarExpandedFrame: CGRect(x: 0, y: 0, width: 390, height: 56)
            )
        )

        XCTAssertEqual(geometry.panelSize.width, bounds.width, accuracy: 0.5)
    }

    func testCompactHeightClampsAndDeduplicatesOverlappingDetents() throws {
        let geometry = try XCTUnwrap(
            OpenAPPChatPanelGeometry(
                bounds: CGRect(x: 0, y: 0, width: 320, height: 100),
                safeAreaInsets: UIEdgeInsets(top: 20, left: 0, bottom: 34, right: 0),
                inputBarExpandedFrame: CGRect(x: 12, y: 0, width: 296, height: 56)
            )
        )

        XCTAssertEqual(geometry.peekHeight, 80, accuracy: 0.5)
        XCTAssertEqual(geometry.halfHeight, 80, accuracy: 0.5)
        XCTAssertEqual(geometry.fullHeight, 80, accuracy: 0.5)
        XCTAssertEqual(geometry.detentHeights, [80])
        XCTAssertEqual(
            geometry.nearestDetent(to: 80, preferredDetent: .half),
            .half
        )
        XCTAssertEqual(
            geometry.nearestDetent(to: 80, preferredDetent: .full),
            .full
        )
    }

    func testNearestDetentAndClampingUseCurrentGeometry() throws {
        let geometry = try XCTUnwrap(makeGeometry())

        XCTAssertEqual(geometry.nearestDetent(to: geometry.peekHeight + 2), .peek)
        XCTAssertEqual(geometry.nearestDetent(to: geometry.halfHeight + 2), .half)
        XCTAssertEqual(geometry.nearestDetent(to: geometry.fullHeight - 2), .full)
        XCTAssertEqual(geometry.clampedDisplayHeight(-100), geometry.peekHeight)
        XCTAssertEqual(geometry.clampedDisplayHeight(10_000), geometry.fullHeight)
    }

    func testListViewportCompensatesForHiddenFixedPanelHeight() {
        let listView = OpenAPPChatMessageListView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 700)
        )

        XCTAssertTrue(
            listView.updateViewport(
                panelHeight: 700,
                displayHeight: 350,
                bottomAvoidingInset: 100
            )
        )
        XCTAssertEqual(listView.participantScrollView.contentInset.bottom, 450, accuracy: 0.5)
        XCTAssertFalse(
            listView.updateViewport(
                panelHeight: 700,
                displayHeight: 350,
                bottomAvoidingInset: 100
            )
        )

        XCTAssertTrue(
            listView.updateViewport(
                panelHeight: 700,
                displayHeight: 700,
                bottomAvoidingInset: 100
            )
        )
        XCTAssertEqual(listView.participantScrollView.contentInset.bottom, 100, accuracy: 0.5)
    }

    func testCoordinatorInstallsFixedPanelAndStartsAtHalfDetent() throws {
        let coordinator = OpenAPPChatPanelCoordinator()
        coordinator.updateLayout(
            bounds: bounds,
            safeAreaInsets: safeAreaInsets,
            inputBarExpandedFrame: inputBarExpandedFrame,
            bottomAvoidingInset: 102
        )
        let geometry = try XCTUnwrap(makeGeometry())

        XCTAssertTrue(coordinator.dragScrollView.panelView === coordinator.panelView)
        XCTAssertEqual(coordinator.dragScrollView.detentHeights, geometry.detentHeights)
        XCTAssertEqual(coordinator.panelView.bounds.size.width, geometry.panelSize.width, accuracy: 0.5)
        XCTAssertEqual(coordinator.panelView.bounds.size.height, geometry.panelSize.height, accuracy: 0.5)
        XCTAssertEqual(coordinator.dragScrollView.displayHeight, geometry.halfHeight, accuracy: 0.5)
        XCTAssertEqual(
            coordinator.panelView.listView.participantScrollView.contentInset.bottom,
            102 + geometry.fullHeight - geometry.halfHeight,
            accuracy: 0.5
        )
    }

    func testCoordinatorProgrammaticMoveUsesBusinessDetent() throws {
        let coordinator = OpenAPPChatPanelCoordinator()
        coordinator.updateLayout(
            bounds: bounds,
            safeAreaInsets: safeAreaInsets,
            inputBarExpandedFrame: inputBarExpandedFrame,
            bottomAvoidingInset: 102
        )
        let geometry = try XCTUnwrap(makeGeometry())

        coordinator.move(to: .peek, animated: false)

        XCTAssertEqual(coordinator.dragScrollView.displayHeight, geometry.peekHeight, accuracy: 0.5)
    }

    func testCoordinatorPreservesMoveRequestedBeforeFirstLayout() throws {
        let coordinator = OpenAPPChatPanelCoordinator()
        coordinator.move(to: .full, animated: false)
        coordinator.updateLayout(
            bounds: bounds,
            safeAreaInsets: safeAreaInsets,
            inputBarExpandedFrame: inputBarExpandedFrame,
            bottomAvoidingInset: 102
        )
        let geometry = try XCTUnwrap(makeGeometry())

        XCTAssertEqual(coordinator.dragScrollView.displayHeight, geometry.fullHeight, accuracy: 0.5)
    }

    private func makeGeometry() -> OpenAPPChatPanelGeometry? {
        OpenAPPChatPanelGeometry(
            bounds: bounds,
            safeAreaInsets: safeAreaInsets,
            inputBarExpandedFrame: inputBarExpandedFrame
        )
    }
}
#endif
