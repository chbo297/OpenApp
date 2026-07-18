#if canImport(UIKit)
import XCTest
@testable import OpenAPP

/// inputBar frame 策略的边界测试：展开 resize 条件约束与收起 move 橡皮筋效果。
final class OpenAPPInputBarFramePolicyTests: XCTestCase {

    private var context: OpenAPPInputBarFramePolicy.Context {
        OpenAPPInputBarFramePolicy.Context(
            bounds: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            safeAreaInsets: .zero,
            keyboardHeight: 0,
            storedExpandedWidth: nil,
            storedCollapsedPlacement: nil
        )
    }

    func testExpandedResizeRubberBandsPastPreferredDisplayWidthWhenCustomizationIsDisabled() {
        let proposedFrame = CGRect(x: 100, y: 744, width: 700, height: 56)

        let result = OpenAPPInputBarFramePolicy.constrainedExpandedResizeFrame(
            proposedFrame,
            allowsWidthCustomization: false,
            context: context
        )
        let strictResult = OpenAPPInputBarFramePolicy.strictlyConstrainedExpandedResizeFrame(
            result,
            allowsWidthCustomization: false,
            context: context
        )

        XCTAssertEqual(result.maxX, proposedFrame.maxX, accuracy: 0.001)
        XCTAssertLessThan(result.minX, 200)
        XCTAssertGreaterThan(result.width, 600)
        XCTAssertLessThan(result.width, proposedFrame.width)
        XCTAssertTrue(OpenAPPInputBarFramePolicy.isExpandedResizeOverdragged(result, context: context))
        XCTAssertEqual(strictResult.minX, 200, accuracy: 0.001)
        XCTAssertEqual(strictResult.width, 600, accuracy: 0.001)
    }

    func testExpandedResizeKeepsGrowingRightwardWhenWidthCustomizationIsEnabled() {
        let proposedFrame = CGRect(x: -100, y: 744, width: 600, height: 56)

        let result = OpenAPPInputBarFramePolicy.constrainedExpandedResizeFrame(
            proposedFrame,
            allowsWidthCustomization: true,
            context: context
        )

        XCTAssertEqual(result.minX, 12, accuracy: 0.001)
        XCTAssertEqual(result.width, proposedFrame.width, accuracy: 0.001)
        XCTAssertGreaterThan(result.maxX, proposedFrame.maxX)
    }

    func testExpandedResizeCompressesIncreasingLeftOverdrag() {
        let rightEdge: CGFloat = 800
        let maximumLegalWidth: CGFloat = 600
        let nearFrame = CGRect(
            x: rightEdge - maximumLegalWidth - 50,
            y: 744,
            width: maximumLegalWidth + 50,
            height: 56
        )
        let farFrame = CGRect(
            x: rightEdge - maximumLegalWidth - 100,
            y: 744,
            width: maximumLegalWidth + 100,
            height: 56
        )
        let nearResult = OpenAPPInputBarFramePolicy.constrainedExpandedResizeFrame(
            nearFrame,
            allowsWidthCustomization: false,
            context: context
        )
        let farResult = OpenAPPInputBarFramePolicy.constrainedExpandedResizeFrame(
            farFrame,
            allowsWidthCustomization: false,
            context: context
        )
        let nearVisualOverdrag = nearResult.width - maximumLegalWidth
        let farVisualOverdrag = farResult.width - maximumLegalWidth

        XCTAssertGreaterThan(nearVisualOverdrag, 0)
        XCTAssertLessThan(nearVisualOverdrag, 50)
        XCTAssertGreaterThan(farVisualOverdrag, nearVisualOverdrag)
        XCTAssertLessThan(farVisualOverdrag - nearVisualOverdrag, nearVisualOverdrag)
        XCTAssertLessThan(farVisualOverdrag, OpenAPPInputBarFramePolicy.edgeRubberBandLimit)
    }

    func testExpandedResizeStartsRubberBandImmediatelyPastPreferredWidth() {
        let preferredFrame = CGRect(x: 200, y: 744, width: 600, height: 56)
        let onePointOverFrame = CGRect(x: 199, y: 744, width: 601, height: 56)
        let preferredResult = OpenAPPInputBarFramePolicy.constrainedExpandedResizeFrame(
            preferredFrame,
            allowsWidthCustomization: false,
            context: context
        )
        let overdragResult = OpenAPPInputBarFramePolicy.constrainedExpandedResizeFrame(
            onePointOverFrame,
            allowsWidthCustomization: false,
            context: context
        )

        XCTAssertEqual(preferredResult, preferredFrame)
        XCTAssertGreaterThan(overdragResult.width, preferredFrame.width)
        XCTAssertLessThan(overdragResult.width, onePointOverFrame.width)
        XCTAssertEqual(overdragResult.maxX, preferredFrame.maxX, accuracy: 0.001)
    }

    func testZeroVelocityResizeDecisionChangesOnBothSidesOfMidpoint() {
        let expandedFrame = CGRect(x: 200, y: 744, width: 600, height: 56)
        let collapsedDecisionFrame = CGRect(x: 473, y: 744, width: 327, height: 56)

        XCTAssertFalse(OpenAPPInputBarFramePolicy.shouldCollapseExpanded(
            velocityX: 0,
            frame: expandedFrame,
            context: context
        ))
        XCTAssertTrue(OpenAPPInputBarFramePolicy.shouldCollapseExpanded(
            velocityX: 0,
            frame: collapsedDecisionFrame,
            context: context
        ))
        XCTAssertFalse(OpenAPPInputBarFramePolicy.shouldCollapseExpanded(
            velocityX: 0,
            frame: expandedFrame,
            context: context
        ))
    }

    func testCollapsedRubberBandLeavesLegalPositionUnchanged() {
        let proposedFrame = CGRect(x: 120, y: 300, width: 56, height: 56)

        let result = OpenAPPInputBarFramePolicy.rubberBandedCollapsedMoveFrame(
            proposedFrame,
            context: context
        )

        XCTAssertEqual(result, proposedFrame)
    }

    func testCollapsedRubberBandCompressesIncreasingLeftOverdrag() {
        let available = OpenAPPInputBarFramePolicy.availableFrame(in: context, avoidingKeyboard: false)
        let nearFrame = CGRect(
            x: available.minX - 50,
            y: 300,
            width: OpenAPPInputBar.collapsedMinWidth,
            height: OpenAPPInputBar.barHeight
        )
        let farFrame = nearFrame.offsetBy(dx: -50, dy: 0)

        let nearResult = OpenAPPInputBarFramePolicy.rubberBandedCollapsedMoveFrame(
            nearFrame,
            context: context
        )
        let farResult = OpenAPPInputBarFramePolicy.rubberBandedCollapsedMoveFrame(
            farFrame,
            context: context
        )
        let nearVisualOverdrag = available.minX - nearResult.minX
        let farVisualOverdrag = available.minX - farResult.minX

        XCTAssertGreaterThan(nearVisualOverdrag, 0)
        XCTAssertLessThan(nearVisualOverdrag, 50)
        XCTAssertGreaterThan(farVisualOverdrag, nearVisualOverdrag)
        XCTAssertLessThan(farVisualOverdrag - nearVisualOverdrag, nearVisualOverdrag)
        XCTAssertLessThan(farVisualOverdrag, OpenAPPInputBarFramePolicy.edgeRubberBandLimit)
    }

    func testCollapsedRubberBandReturnsToStrictBoundaryWhenConstrained() {
        let available = OpenAPPInputBarFramePolicy.availableFrame(in: context, avoidingKeyboard: false)
        let proposedFrame = CGRect(
            x: available.maxX + 100,
            y: available.maxY + 100,
            width: OpenAPPInputBar.collapsedMinWidth,
            height: OpenAPPInputBar.barHeight
        )
        let rubberFrame = OpenAPPInputBarFramePolicy.rubberBandedCollapsedMoveFrame(
            proposedFrame,
            context: context
        )
        let constrainedFrame = OpenAPPInputBarFramePolicy.constrainedCollapsedFrame(
            rubberFrame,
            context: context
        )

        XCTAssertGreaterThan(rubberFrame.maxX, available.maxX)
        XCTAssertGreaterThan(rubberFrame.maxY, available.maxY)
        XCTAssertEqual(constrainedFrame.maxX, available.maxX, accuracy: 0.001)
        XCTAssertEqual(constrainedFrame.maxY, available.maxY, accuracy: 0.001)
    }

    func testCollapsedRubberBandRawFrameRoundTripsDisplayedFrame() {
        let available = OpenAPPInputBarFramePolicy.availableFrame(in: context, avoidingKeyboard: false)
        let rawFrame = CGRect(
            x: available.minX - 120,
            y: available.maxY + 80,
            width: OpenAPPInputBar.collapsedMinWidth,
            height: OpenAPPInputBar.barHeight
        )
        let displayedFrame = OpenAPPInputBarFramePolicy.rubberBandedCollapsedMoveFrame(
            rawFrame,
            context: context
        )
        let reconstructedRawFrame = OpenAPPInputBarFramePolicy.rawCollapsedMoveFrame(
            from: displayedFrame,
            context: context
        )
        let reconstructedDisplayedFrame = OpenAPPInputBarFramePolicy.rubberBandedCollapsedMoveFrame(
            reconstructedRawFrame,
            context: context
        )

        XCTAssertEqual(reconstructedDisplayedFrame.minX, displayedFrame.minX, accuracy: 0.001)
        XCTAssertEqual(reconstructedDisplayedFrame.minY, displayedFrame.minY, accuracy: 0.001)
    }

    func testInterruptedCollapsedReboundCanResumeFromCurrentDisplayedFrame() {
        let available = OpenAPPInputBarFramePolicy.availableFrame(in: context, avoidingKeyboard: false)
        let rawFrame = CGRect(
            x: available.minX - 100,
            y: 300,
            width: OpenAPPInputBar.collapsedMinWidth,
            height: OpenAPPInputBar.barHeight
        )
        let displayedFrame = OpenAPPInputBarFramePolicy.rubberBandedCollapsedMoveFrame(
            rawFrame,
            context: context
        )
        let reconstructedRawFrame = OpenAPPInputBarFramePolicy.rawCollapsedMoveFrame(
            from: displayedFrame,
            context: context
        )
        var tracking = OpenAPPCollapsedInputBarMoveTracking(
            displayedAnchorFrame: displayedFrame,
            rawAnchorFrame: reconstructedRawFrame
        )
        let resumedRawFrame = tracking.rawFrame(for: displayedFrame)
        let resumedDisplayedFrame = OpenAPPInputBarFramePolicy.rubberBandedCollapsedMoveFrame(
            resumedRawFrame,
            context: context
        )

        XCTAssertEqual(resumedDisplayedFrame.minX, displayedFrame.minX, accuracy: 0.001)
        XCTAssertEqual(resumedDisplayedFrame.minY, displayedFrame.minY, accuracy: 0.001)
    }

    func testExpandedResizeRawFrameRoundTripsDisplayedOverdrag() {
        let rawFrame = CGRect(x: 100, y: 744, width: 700, height: 56)
        let displayedFrame = OpenAPPInputBarFramePolicy.constrainedExpandedResizeFrame(
            rawFrame,
            allowsWidthCustomization: false,
            context: context
        )
        let reconstructedRawFrame = OpenAPPInputBarFramePolicy.rawExpandedResizeFrame(
            from: displayedFrame,
            context: context
        )
        let reconstructedDisplayedFrame = OpenAPPInputBarFramePolicy.constrainedExpandedResizeFrame(
            reconstructedRawFrame,
            allowsWidthCustomization: false,
            context: context
        )

        XCTAssertEqual(reconstructedDisplayedFrame.minX, displayedFrame.minX, accuracy: 0.001)
        XCTAssertEqual(reconstructedDisplayedFrame.maxX, displayedFrame.maxX, accuracy: 0.001)
        XCTAssertEqual(reconstructedDisplayedFrame.width, displayedFrame.width, accuracy: 0.001)
    }

    func testInterruptedExpandedReboundCanResumeFromCurrentDisplayedFrame() {
        let rawFrame = CGRect(x: 100, y: 744, width: 700, height: 56)
        let displayedFrame = OpenAPPInputBarFramePolicy.constrainedExpandedResizeFrame(
            rawFrame,
            allowsWidthCustomization: false,
            context: context
        )
        let reconstructedRawFrame = OpenAPPInputBarFramePolicy.rawExpandedResizeFrame(
            from: displayedFrame,
            context: context
        )
        var tracking = OpenAPPExpandedInputBarResizeTracking(
            displayedAnchorFrame: displayedFrame,
            rawAnchorFrame: reconstructedRawFrame
        )
        let resumedRawFrame = tracking.rawFrame(for: displayedFrame)
        let resumedDisplayedFrame = OpenAPPInputBarFramePolicy.constrainedExpandedResizeFrame(
            resumedRawFrame,
            allowsWidthCustomization: false,
            context: context
        )

        XCTAssertEqual(resumedDisplayedFrame.minX, displayedFrame.minX, accuracy: 0.001)
        XCTAssertEqual(resumedDisplayedFrame.maxX, displayedFrame.maxX, accuracy: 0.001)
        XCTAssertEqual(resumedDisplayedFrame.width, displayedFrame.width, accuracy: 0.001)
    }
}
#endif
