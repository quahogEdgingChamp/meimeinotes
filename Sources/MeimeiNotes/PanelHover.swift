import Foundation

struct PanelHover {
    private let openedAtHotZone: Bool
    private var hasEntered = false
    private var leftAt: TimeInterval?

    init(openedAtHotZone: Bool = false) {
        self.openedAtHotZone = openedAtHotZone
    }

    mutating func shouldDismiss(at time: TimeInterval, insidePanel: Bool, insideHotZone: Bool,
                                interactionInProgress: Bool) -> Bool {
        if insidePanel { hasEntered = true }

        if insidePanel || interactionInProgress || (openedAtHotZone && !hasEntered && insideHotZone) {
            leftAt = nil
            return false
        }

        guard openedAtHotZone || hasEntered else { return false }
        let departure = leftAt ?? time
        leftAt = departure
        let gracePeriod = hasEntered ? 0.25 : 0.85
        return time - departure >= gracePeriod
    }
}
