import AppKit

@MainActor
final class HotZoneMonitor {
    private let onEnter: (NSScreen) -> Void
    private let onPointer: (CGPoint, Bool, TimeInterval) -> Void
    private var preferences = PreferenceValues()
    private var pollingTimer: Timer?
    private var tracksPanel = false
    private var hoveredScreen: CGRect?
    private var enteredAt: TimeInterval = 0
    private var hasOpened = false

    init(onEnter: @escaping (NSScreen) -> Void, onPointer: @escaping (CGPoint, Bool, TimeInterval) -> Void) {
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
        tracksPanel = value
        updatePolling()
    }

    private func updatePolling() {
        let shouldPoll = preferences.hotZoneEnabled || tracksPanel
        if shouldPoll, pollingTimer == nil {
            let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.samplePointer() }
            }
            timer.tolerance = 0.035
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
            ?? screens.first { $0.frame.contains(pointer) }
    }

    private func samplePointer() {
        let pointer = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let hotScreen = preferences.hotZoneEnabled ? Self.screen(at: pointer).flatMap { screen in
            preferences.isInHotZone(pointer, screen: screen.frame) ? screen : nil
        } : nil

        if tracksPanel { onPointer(pointer, hotScreen != nil, now) }

        guard NSEvent.pressedMouseButtons == 0, let screen = hotScreen else {
            hoveredScreen = nil
            return
        }

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

