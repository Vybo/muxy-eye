import CoreGraphics
import MuxyEyeCore
import Observation
import SwiftUI

/// What the eye's view draws and how it moves, in screen coordinates. The window controller sets it;
/// the view lays it out on a stage that covers everything the eye can draw on the screen, so nothing
/// the view animates depends on the window's frame.
@MainActor @Observable
final class EyeStage {
    /// The stage on screen, within the screen. At the eye's default spot its top is the top of the screen.
    var frame: CGRect = .zero
    var phase: PanelPhase = .collapsed
    /// The panel is opening again before it finished closing: its content comes straight back
    /// instead of cascading in.
    var reopening = false

    var collapsed = CollapsedLayout(panelFrame: .zero, eyeFrame: .zero, countFrame: nil, shapeFrame: nil)
    /// How the collapsed eye moves to a new layout; nil jumps.
    var collapsedMotion: Animation?

    var expandedFrame: CGRect = .zero
    /// Room left at the top of the panel for the physical notch.
    var topInset: CGFloat = 0
    /// The expanded panel covers the eye, whose signal line and count then fade into it: below an eye
    /// in the menu bar, or when neither side has room. An eye beside the panel keeps showing.
    var eyeCovered = true

    /// The panel's black shape: on the eye at rest collapsed, the panel's frame when expanded.
    var panelOutline = EyeOutline(frame: .zero, topRadius: 0, bottomRadius: 0)
    var panelMotion: Animation?
    /// The panel's shape and content; 0 at rest collapsed, where the eye's own shape shows.
    var panelOpacity: Double = 0
    var panelOpacityMotion: Animation?

    /// `rect`, in screen coordinates, in the stage's view.
    func local(_ rect: CGRect) -> CGRect {
        EyeLayout.stageRect(rect, in: frame)
    }

    func local(_ outline: EyeOutline) -> EyeOutline {
        EyeOutline(frame: local(outline.frame), topRadius: outline.topRadius, bottomRadius: outline.bottomRadius)
    }
}
