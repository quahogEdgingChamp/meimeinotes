import Combine
import Foundation

@MainActor
final class FocusTimer: ObservableObject {
    struct Countdown: Codable, Equatable {
        var duration: Int
        var remaining: TimeInterval
        var deadline: Date?
    }

    enum Phase {
        case ready, running, paused, finished
    }

    static let maximumDuration = 99 * 60 + 59
    static let presets = [5, 15, 25]

    @Published private(set) var countdown: Countdown
    @Published private(set) var secondsRemaining: Int
    var onFinish: (() -> Void)?

    private static let key = "focusTimer"
    private let defaults: UserDefaults
    private var ticker: Timer?

    var phase: Phase {
        if countdown.deadline != nil { return .running }
        if secondsRemaining == 0 { return .finished }
        return countdown.remaining == Double(countdown.duration) ? .ready : .paused
    }

    var display: String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    var progress: Double { 1 - Double(secondsRemaining) / Double(countdown.duration) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initial: Countdown
        if let data = defaults.data(forKey: Self.key),
           let restored = try? JSONDecoder().decode(Countdown.self, from: data),
           (1...Self.maximumDuration).contains(restored.duration),
           (0...Double(restored.duration)).contains(restored.remaining) {
            initial = restored
        } else {
            initial = Countdown(duration: 25 * 60, remaining: 25 * 60)
        }
        countdown = initial
        secondsRemaining = Int(ceil(initial.remaining))
        refresh()
        if countdown.deadline != nil { startTicker() }
    }

    func setDuration(_ seconds: Int) {
        guard (1...Self.maximumDuration).contains(seconds) else { return }
        stopTicker()
        save(Countdown(duration: seconds, remaining: Double(seconds)))
    }

    func reset() { setDuration(countdown.duration) }

    func toggle() {
        if let deadline = countdown.deadline {
            let remaining = timeLeft(until: deadline)
            stopTicker()
            save(Countdown(duration: countdown.duration, remaining: remaining))
            if remaining == 0 { onFinish?() }
        } else {
            let remaining = countdown.remaining > 0 ? countdown.remaining : Double(countdown.duration)
            save(Countdown(duration: countdown.duration, remaining: remaining, deadline: .now + remaining))
            startTicker()
        }
    }

    private func refresh() {
        guard let deadline = countdown.deadline else { return }
        let remaining = timeLeft(until: deadline)
        if remaining <= 0 {
            stopTicker()
            save(Countdown(duration: countdown.duration, remaining: 0))
            onFinish?()
        } else {
            let seconds = Int(ceil(remaining))
            if seconds != secondsRemaining { secondsRemaining = seconds }
        }
    }

    private func timeLeft(until deadline: Date) -> TimeInterval {
        min(Double(countdown.duration), max(0, deadline.timeIntervalSinceNow))
    }

    private func save(_ value: Countdown) {
        countdown = value
        secondsRemaining = Int(ceil(value.remaining))
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private func startTicker() {
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.06
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
