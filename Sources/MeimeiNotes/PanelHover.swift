import CoreGraphics
import Foundation

struct PanelHover {
    private var pointerAtManualOpen: CGPoint?
    private var hasEntered = false
    private var leftAt: TimeInterval?

    init(openedAtHotZone: Bool, pointer: CGPoint) {
        pointerAtManualOpen = openedAtHotZone ? nil : pointer
    }

    mutating func shouldDismiss(at time: TimeInterval, pointer: CGPoint, insidePanel: Bool, insideHotZone: Bool,
                                interactionInProgress: Bool) -> Bool {
        if insidePanel { hasEntered = true }
        if let pointerAtManualOpen, insidePanel || pointer != pointerAtManualOpen {
            self.pointerAtManualOpen = nil
        }

        // The pointer in a hot zone is asking for the panel, so it stays open there.
        if insidePanel || insideHotZone || pointerAtManualOpen != nil || interactionInProgress {
            leftAt = nil
            return false
        }

        let departure = leftAt ?? time
        leftAt = departure
        let gracePeriod = hasEntered ? 0.25 : 0.85
        return time - departure >= gracePeriod
    }
}
