import CoreGraphics
import Testing
@testable import MuxyEyeCore

@Suite struct PanelPhaseTests {
    @Test func expandingStartsAnOpeningAndCollapsingAClosing() {
        #expect(PanelPhase.collapsed.requesting(expanded: true) == .opening)
        #expect(PanelPhase.expanded.requesting(expanded: false) == .closing)
    }

    @Test func aReversedRequestTurnsTheTransitionAround() {
        #expect(PanelPhase.opening.requesting(expanded: false) == .closing)
        #expect(PanelPhase.closing.requesting(expanded: true) == .opening)
    }

    @Test func aRepeatedRequestChangesNothing() {
        #expect(PanelPhase.opening.requesting(expanded: true) == .opening)
        #expect(PanelPhase.expanded.requesting(expanded: true) == .expanded)
        #expect(PanelPhase.closing.requesting(expanded: false) == .closing)
        #expect(PanelPhase.collapsed.requesting(expanded: false) == .collapsed)
    }

    @Test func transitionsSettleAtTheirEnd() {
        #expect(PanelPhase.opening.settled == .expanded)
        #expect(PanelPhase.closing.settled == .collapsed)
        #expect(PanelPhase.expanded.settled == .expanded)
        #expect(PanelPhase.collapsed.settled == .collapsed)
    }

    @Test func rapidTogglesEndWhereTheLastRequestPoints() {
        let requests = [true, false, true, false, true, true, false, true]
        let phase = requests.reduce(PanelPhase.collapsed) { $0.requesting(expanded: $1) }
        #expect(phase == .opening)
        #expect(phase.settled == .expanded)
    }

    @Test func panelAndEyeAreBothDrawnWhileMoving() {
        #expect(PanelPhase.collapsed.showsPanel == false)
        #expect(PanelPhase.collapsed.showsEye)
        #expect(PanelPhase.opening.showsPanel)
        #expect(PanelPhase.opening.showsEye)
        #expect(PanelPhase.expanded.showsPanel)
        #expect(PanelPhase.expanded.showsEye == false)
        #expect(PanelPhase.closing.showsPanel)
        #expect(PanelPhase.closing.showsEye)
        #expect(PanelPhase.opening.isExpanding)
        #expect(PanelPhase.closing.isExpanding == false)
    }

    @Test func footprintIncludesThePanelOnlyWhileExpanding() {
        let collapsed = CollapsedLayout(
            panelFrame: CGRect(x: 300, y: 960, width: 40, height: 20),
            eyeFrame: CGRect(x: 0, y: 0, width: 20, height: 20),
            countFrame: nil,
            shapeFrame: nil)
        let expanded = CGRect(x: 0, y: 700, width: 640, height: 280)
        #expect(PanelPhase.collapsed.footprint(collapsed: collapsed, expanded: expanded) == collapsed.panelFrame)
        #expect(PanelPhase.closing.footprint(collapsed: collapsed, expanded: expanded) == collapsed.panelFrame)
        #expect(PanelPhase.opening.footprint(collapsed: collapsed, expanded: expanded) == expanded)
        #expect(PanelPhase.expanded.footprint(collapsed: collapsed, expanded: expanded) == expanded)
        let wide = CollapsedLayout(
            panelFrame: CGRect(x: -10, y: 960, width: 40, height: 20),
            eyeFrame: .zero, countFrame: nil, shapeFrame: nil)
        #expect(PanelPhase.expanded.footprint(collapsed: wide, expanded: expanded) == expanded.union(wide.panelFrame))
    }
}
