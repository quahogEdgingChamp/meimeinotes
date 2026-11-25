import Foundation
import UserNotifications

enum TimerNotificationPlan: Equatable {
    case clear
    case schedule(Date)
    case leavePending

    init(enabled: Bool, countdown: FocusTimer.Countdown) {
        if !enabled {
            self = .clear
        } else if let deadline = countdown.deadline {
            self = .schedule(deadline)
        } else {
            self = countdown.remaining == 0 ? .leavePending : .clear
        }
    }
}

@MainActor
final class TimerNotifications: NSObject, UNUserNotificationCenterDelegate {
    private static let identifier = "timer-finished"
    private let center = UNUserNotificationCenter.current()
    private let openPanel: () -> Void
    private var desiredPlan: TimerNotificationPlan?
    private var isReconciling = false

    init(openPanel: @escaping () -> Void) {
        self.openPanel = openPanel
        super.init()
        center.delegate = self
    }

    func apply(_ plan: TimerNotificationPlan) {
        // Let an in-flight request finish if the timer expires while macOS is asking for permission.
        if plan == .leavePending, case .schedule(_)? = desiredPlan { return }
        guard plan != desiredPlan else { return }
        desiredPlan = plan

        if plan == .clear { clearPending() }
        guard !isReconciling else { return }
        isReconciling = true
        Task { await reconcile() }
    }

    private func reconcile() async {
        defer { isReconciling = false }
        // Sequence changes so a late add can't outlive a pause or reset.
        while let plan = desiredPlan {
            switch plan {
            case .clear: clearPending()
            case .schedule(let deadline): await schedule(deadline)
            case .leavePending: break
            }
            if plan == desiredPlan { return }
        }
    }

    private func schedule(_ deadline: Date) async {
        let plan = TimerNotificationPlan.schedule(deadline)
        let settings = await center.notificationSettings()
        guard plan == desiredPlan else { return }

        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
        } else if settings.authorizationStatus == .denied {
            return
        }

        guard plan == desiredPlan else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time’s up"
        let timeLeft = deadline.timeIntervalSinceNow
        let trigger = timeLeft > 0 ? UNTimeIntervalNotificationTrigger(timeInterval: timeLeft, repeats: false) : nil
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func clearPending() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await MainActor.run { openPanel() }
        }
    }
}
