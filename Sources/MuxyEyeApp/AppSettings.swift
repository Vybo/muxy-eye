import CoreGraphics
import Foundation
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoExpand = defaults.bool(forKey: Key.autoExpand)
        pinnedDisplayID = (defaults.object(forKey: Key.pinnedDisplayID) as? NSNumber)?.uint32Value
        muxyPathOverride = defaults.string(forKey: Key.muxyPathOverride)
        muxyProfileDir = defaults.string(forKey: Key.muxyProfileDir)
        didOnboard = defaults.bool(forKey: Key.didOnboard)
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
