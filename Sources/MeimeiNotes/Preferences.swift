import Combine
import CoreGraphics
import Foundation

struct TriggerPoint: Codable, Equatable {
    var x: Double
    var y: Double

    func position(in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + frame.width * x, y: frame.maxY - frame.height * y)
    }

    func panelOrigin(for size: CGSize, screen: CGRect, visibleFrame: CGRect) -> CGPoint {
        let available = visibleFrame.insetBy(dx: 12, dy: 12)
        let anchor = position(in: screen)
        return CGPoint(
            x: max(available.minX, min(anchor.x - size.width * x, available.maxX - size.width)),
            y: max(available.minY, min(anchor.y - size.height * (1 - y), available.maxY - size.height))
        )
    }
}

enum TriggerLocation: String, Codable, CaseIterable, Identifiable {
    case bottomLeft, bottomRight, topLeft, topRight, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .custom: "Custom spot"
        }
    }

    func point(custom: TriggerPoint) -> TriggerPoint {
        switch self {
        case .bottomLeft: TriggerPoint(x: 0, y: 1)
        case .bottomRight: TriggerPoint(x: 1, y: 1)
        case .topLeft: TriggerPoint(x: 0, y: 0)
        case .topRight: TriggerPoint(x: 1, y: 0)
        case .custom: custom
        }
    }
}

enum ClockMode: String, Codable, CaseIterable, Identifiable {
    case timer, stopwatch

    var id: Self { self }

    var title: String {
        switch self {
        case .timer: "Timer"
        case .stopwatch: "Stopwatch"
        }
    }
}

struct PreferenceValues: Codable, Equatable {
    var hotZoneEnabled = true
    var triggerLocation = TriggerLocation.bottomLeft
    var customPoint = TriggerPoint(x: 0.5, y: 1)
    var catEnabled = false
    var timerSound = true
    private var timerNotificationPreference: Bool?
    private var clockModePreference: ClockMode?

    var timerNotifications: Bool {
        get { timerNotificationPreference ?? true }
        set { timerNotificationPreference = newValue }
    }

    var clockMode: ClockMode {
        get { clockModePreference ?? .timer }
        set { clockModePreference = newValue }
    }

    var triggerPoint: TriggerPoint { triggerLocation.point(custom: customPoint) }

    func isInHotZone(_ pointer: CGPoint, screen: CGRect, cameraHousing: CGRect? = nil) -> Bool {
        guard (screen.minX...screen.maxX).contains(pointer.x),
              (screen.minY...screen.maxY).contains(pointer.y) else { return false }
        let trigger = triggerPoint.position(in: screen)
        let radius: CGFloat = triggerLocation == .custom ? 22 : 18
        guard abs(pointer.x - trigger.x) <= radius else { return false }
        if let cameraHousing, trigger.y >= cameraHousing.minY,
           (cameraHousing.minX...cameraHousing.maxX).contains(trigger.x) {
            return pointer.y >= cameraHousing.minY - radius
        }
        return abs(pointer.y - trigger.y) <= radius
    }
}

@MainActor
final class Preferences: ObservableObject {
    @Published var values: PreferenceValues {
        didSet {
            if let data = try? JSONEncoder().encode(values) {
                defaults.set(data, forKey: Self.key)
            }
        }
    }

    private static let key = "preferences"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let restored = try? JSONDecoder().decode(PreferenceValues.self, from: data) {
            values = restored
        } else {
            values = PreferenceValues()
        }
    }
}

