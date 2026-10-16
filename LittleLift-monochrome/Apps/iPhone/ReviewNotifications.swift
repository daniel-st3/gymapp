import UserNotifications

@MainActor final class ReviewNotifications: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (() -> Void)?
    override init() { super.init(); UNUserNotificationCenter.current().delegate = self }
    func requestPermission() async throws {
        let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        guard allowed else { throw WorkoutError.invalidState(L10n.s("Review notifications are off. The one-tap review action remains available in Little Lift.")) }
    }
    private var generation = 0
    func cancelPending() async {
        generation += 1
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("littlelift.review.") })
    }
    func schedule(sessionID: UUID) async throws {
        let expectedGeneration = generation
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { throw WorkoutError.invalidState(L10n.s("Allow review notifications in iPhone Settings, or use the review action in Little Lift.")) }
        guard expectedGeneration == generation else { throw CancellationError() }
        let content = UNMutableNotificationContent()
        content.title = L10n.s("Little Lift workout ready"); content.subtitle = L10n.s("Coach review")
        content.body = L10n.s("Your completed workout is saved on this iPhone. Open to review.")
        content.userInfo = ["reviewSessionID": sessionID.uuidString]
        // Stable identifier replaces a pending duplicate if a crash occurs between
        // notification registration and the persisted notified flag.
        let identifier = "littlelift.review.\(sessionID)"
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        if expectedGeneration != generation {
            center.removePendingNotificationRequests(withIdentifiers: [identifier]); throw CancellationError()
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { self.onOpen?() }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list] }
}
