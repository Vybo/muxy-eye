import CoreGraphics
import Foundation
import MuxyEyeCore
import Observation

/// User preferences, persisted in `UserDefaults`.
@MainActor @Observable
final class AppSettings {
    private enum Key {
        static let autoExpand = "autoExpand"
        static let pinnedDisplayID = "pinnedDisplayID"
        static let muxyPathOverride = "muxyPathOverride"
        static let muxyProfileDir = "muxyProfileDir"
        static let didOnboard = "didOnboard"
        static let eyePosition = "eyePosition"
        static let eyeScale = "eyeScale"
        static let panelSide = "panelSide"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var autoExpand: Bool {
        didSet { defaults.set(autoExpand, forKey: Key.autoExpand) }
    }

    /// The display the eye is pinned to; nil follows the focused app (`NSScreen.main`).
    var pinnedDisplayID: CGDirectDisplayID? {
        didSet { store(pinnedDisplayID.map { NSNumber(value: $0) }, forKey: Key.pinnedDisplayID) }
    }

    var muxyPathOverride: String? {
        didSet { store(muxyPathOverride, forKey: Key.muxyPathOverride) }
    }

    /// Passed to the Muxy CLI as `MUXY_DIR`.
    var muxyProfileDir: String? {
        didSet { store(muxyProfileDir, forKey: Key.muxyProfileDir) }
    }

    var didOnboard: Bool {
        didSet { defaults.set(didOnboard, forKey: Key.didOnboard) }
    }

    /// Where the user moved the eye and how large they made it; the default spot and size until then.
    var eyePlacement: EyePlacement {
        didSet {
            guard eyePlacement != oldValue else { return }
            store(eyePlacement.position.map { [Double($0.x), Double($0.y)] }, forKey: Key.eyePosition)
            store(eyePlacement.scale == 1 ? nil : Double(eyePlacement.scale), forKey: Key.eyeScale)
        }
    }

    /// Where the panel opens relative to the eye.
    var panelSide: PanelSide {
        didSet { defaults.set(panelSide.rawValue, forKey: Key.panelSide) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoExpand = defaults.bool(forKey: Key.autoExpand)
        pinnedDisplayID = (defaults.object(forKey: Key.pinnedDisplayID) as? NSNumber)?.uint32Value
        muxyPathOverride = defaults.string(forKey: Key.muxyPathOverride)
        muxyProfileDir = defaults.string(forKey: Key.muxyProfileDir)
        didOnboard = defaults.bool(forKey: Key.didOnboard)
        let position = (defaults.array(forKey: Key.eyePosition) as? [Double]).flatMap { values in
            values.count == 2 ? CGPoint(x: values[0], y: values[1]) : nil
        }
        let scale = (defaults.object(forKey: Key.eyeScale) as? NSNumber)?.doubleValue ?? 1
        eyePlacement = EyePlacement(position: position, scale: scale).sanitized
        panelSide = defaults.string(forKey: Key.panelSide).flatMap(PanelSide.init(rawValue:)) ?? .below
    }

    private func store(_ value: Any?, forKey key: String) {
        if let string = value as? String, string.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
