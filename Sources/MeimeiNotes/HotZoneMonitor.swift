import AppKit

@MainActor
final class HotZoneMonitor {
    /// Returns whether the panel opened. A false result is retried while the pointer stays.
    private let onEnter: (NSScreen) -> Bool
    private let onPointer: (CGPoint, NSScreen?, TimeInterval) -> Void
    private var preferences = PreferenceValues()
    private var pollingTimer: Timer?
    private var tracksPanel = false
    private var hoveredScreen: CGRect?
    private var enteredAt: TimeInterval = 0
    private var hasOpened = false

    init(onEnter: @escaping (NSScreen) -> Bool, onPointer: @escaping (CGPoint, NSScreen?, TimeInterval) -> Void) {
        self.onEnter = onEnter
        self.onPointer = onPointer
    }

    func apply(_ values: PreferenceValues) {
        if preferences.triggerLocation != values.triggerLocation || preferences.customPoint != values.customPoint
            || preferences.hotZoneEnabled != values.hotZoneEnabled {
            hoveredScreen = nil
        }
        preferences = values
        updatePolling()
    }

    func trackPanel(_ value: Bool) {
        // Closing the panel with the pointer in the trigger area waits for a fresh pointer entry.
        if tracksPanel && !value, let screen = hotScreen(at: NSEvent.mouseLocation) {
            hoveredScreen = screen.frame
            hasOpened = true
        }
        tracksPanel = value
        updatePolling()
    }

    private func updatePolling() {
        let shouldPoll = preferences.hotZoneEnabled || tracksPanel
        if shouldPoll, pollingTimer == nil {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.samplePointer() }
            }
            timer.tolerance = 0.01
            RunLoop.main.add(timer, forMode: .common)
            pollingTimer = timer
        } else if !shouldPoll {
            pollingTimer?.invalidate()
            pollingTimer = nil
            hoveredScreen = nil
        }
    }

    static func screen(at pointer: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        return screens.first { NSMouseInRect(pointer, $0.frame, false) }
            ?? screens.first { screen in
                (screen.frame.minX...screen.frame.maxX).contains(pointer.x)
                    && (screen.frame.minY...screen.frame.maxY).contains(pointer.y)
            }
    }

    private func hotScreen(at pointer: CGPoint) -> NSScreen? {
        guard preferences.hotZoneEnabled else { return nil }
        let matches = NSScreen.screens.filter { screen in
            preferences.isInHotZone(pointer, screen: screen.frame, cameraHousing: screen.cameraHousing)
        }
        return matches.first { NSMouseInRect(pointer, $0.frame, false) } ?? matches.first
    }

    private func samplePointer() {
        let pointer = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let hotScreen = hotScreen(at: pointer)

        defer {
            if tracksPanel { onPointer(pointer, hotScreen, now) }
        }

        guard let screen = hotScreen else {
            hoveredScreen = nil
            return
        }

        if hoveredScreen != screen.frame {
            hoveredScreen = screen.frame
            enteredAt = now
            hasOpened = false
        } else if NSEvent.pressedMouseButtons != 0 {
            enteredAt = now
        } else if !hasOpened, now - enteredAt >= 0.16 {
            hasOpened = onEnter(screen)
        }
    }
}

private extension NSScreen {
    var cameraHousing: CGRect? {
        let height = safeAreaInsets.top
        guard height > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea,
              right.minX > left.maxX else { return nil }
        return CGRect(x: left.maxX, y: frame.maxY - height, width: right.minX - left.maxX, height: height)
    }
}

