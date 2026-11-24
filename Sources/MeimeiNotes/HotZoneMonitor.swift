import AppKit

@MainActor
final class HotZoneMonitor {
    private let onEnter: (NSScreen) -> Void
    private var preferences = PreferenceValues()
    private var pollingTimer: Timer?
    private var hoveredScreen: CGRect?
    private var enteredAt: TimeInterval = 0
    private var hasOpened = false

    init(onEnter: @escaping (NSScreen) -> Void) {
        self.onEnter = onEnter
    }

    func apply(_ values: PreferenceValues) {
        if preferences.triggerLocation != values.triggerLocation || preferences.customPoint != values.customPoint {
            hoveredScreen = nil
        }
        preferences = values
        if values.hotZoneEnabled, pollingTimer == nil {
            let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.samplePointer() }
            }
            timer.tolerance = 0.035
            RunLoop.main.add(timer, forMode: .common)
            pollingTimer = timer
        } else if !values.hotZoneEnabled {
            pollingTimer?.invalidate()
            pollingTimer = nil
            hoveredScreen = nil
        }
    }

    static func screen(at pointer: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        return screens.first { NSMouseInRect(pointer, $0.frame, false) }
            ?? screens.first { $0.frame.contains(pointer) }
    }

    private func samplePointer() {
        let pointer = NSEvent.mouseLocation
        guard NSEvent.pressedMouseButtons == 0,
              let screen = Self.screen(at: pointer),
              preferences.isInHotZone(pointer, screen: screen.frame) else {
            hoveredScreen = nil
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if hoveredScreen != screen.frame {
            hoveredScreen = screen.frame
            enteredAt = now
            hasOpened = false
        } else if !hasOpened, now - enteredAt >= 0.25 {
            hasOpened = true
            onEnter(screen)
        }
    }
}

