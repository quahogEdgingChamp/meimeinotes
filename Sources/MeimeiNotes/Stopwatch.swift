import Combine
import Foundation

@MainActor
final class Stopwatch: ObservableObject {
    struct Session: Codable, Equatable {
        var accumulated: TimeInterval = 0
        var startedAt: Date?
    }

    enum Phase {
        case ready, running, paused
    }

    @Published private(set) var session: Session
    @Published private(set) var secondsElapsed: Int

    private static let key = "stopwatch"
    private let defaults: UserDefaults
    private var ticker: Timer?

    var phase: Phase {
        if session.startedAt != nil { return .running }
        return session.accumulated > 0 ? .paused : .ready
    }

    var display: String { Self.format(secondsElapsed) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var initial = Session()
        if let data = defaults.data(forKey: Self.key),
           let restored = try? JSONDecoder().decode(Session.self, from: data),
           restored.accumulated.isFinite, restored.accumulated >= 0 {
            initial = restored
        }
        session = initial
        secondsElapsed = Int(Self.elapsed(in: initial))
        if initial.startedAt != nil { startTicker() }
    }

    func toggle() {
        if session.startedAt != nil {
            stopTicker()
            save(Session(accumulated: Self.elapsed(in: session)))
        } else {
            save(Session(accumulated: session.accumulated, startedAt: .now))
            startTicker()
        }
    }

    func reset() {
        stopTicker()
        save(Session())
    }

    static func format(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
            : String(format: "%02d:%02d", minutes, seconds % 60)
    }

    private static func elapsed(in session: Session) -> TimeInterval {
        // Ignore a start time in the future, which a clock change can leave behind.
        session.accumulated + max(0, session.startedAt.map { -$0.timeIntervalSinceNow } ?? 0)
    }

    private func refresh() {
        let seconds = Int(Self.elapsed(in: session))
        if seconds != secondsElapsed { secondsElapsed = seconds }
    }

    private func save(_ value: Session) {
        session = value
        secondsElapsed = Int(Self.elapsed(in: value))
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
