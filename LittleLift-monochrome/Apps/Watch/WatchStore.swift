import Foundation
import Observation
import WatchKit
import UserNotifications

enum WatchSheet: String, Identifiable {
    case options, effort, motion, adjust
    var id: String { rawValue }
}

@MainActor @Observable
final class WatchStore {
    static let shared = WatchStore()
    private(set) var state = WatchState()
    var draftWeight: Double = 0
    var draftReps: Double = 1
    var error: String?
    var presentedSheet: WatchSheet?
    private(set) var storageBlocked = false
    private(set) var syncNote = ""
    private(set) var isSyncing = false
    private(set) var connectionDetails = L10n.s("Connecting…")
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var notificationIssue: String?
    @ObservationIgnored private let repository: FileRepository<WatchState>
    @ObservationIgnored private let link = DeviceLink()
    @ObservationIgnored private let notifications = RestNotifications()
    @ObservationIgnored private var completionUptime: TimeInterval?

    private init() {
        let folder = URL.applicationSupportDirectory.appending(path: "LittleLift", directoryHint: .isDirectory)
        repository = FileRepository(url: folder.appending(path: "watch-v1.json"))
        do { try repository.checkpointBeforeUpgrade(); let loaded = try repository.load() ?? WatchState(); try StorageSchema.validate(loaded.storageVersion); state = loaded; UserDefaults.standard.set(state.comfort?.language, forKey: "littlelift.language") }
        catch { storageBlocked = true; self.error = L10n.s("Stored data could not be read and has not been overwritten. \(error.localizedDescription)") }
        prefill()
        link.onMessage = { [weak self] in try self?.receive($0) }
        link.onReady = { [weak self] in self?.retrySync() }
        link.onStatus = { [weak self] in self?.syncNote = $0 }
        link.onBusy = { [weak self] in self?.isSyncing = $0 }
        link.onDetails = { [weak self] in self?.connectionDetails = $0 }
        link.activate()
    }

    private func commit(_ candidate: WatchState) throws {
        var next = candidate; next.storageVersion = 2
        guard !storageBlocked else { throw WorkoutError.invalidState(L10n.s("Stored data could not be read. Restart after restoring your backup.")) }
        if let active = next.session, active.phase != .completed { try active.validateDeliveryReserve() }
        let changedExercise = state.session?.currentExercise?.id != next.session?.currentExercise?.id
        let justCompleted = state.session?.phase != .completed && next.session?.phase == .completed
        try repository.save(next); state = next
        if justCompleted { completionUptime = ProcessInfo.processInfo.systemUptime }
        if changedExercise { WorkoutRuntime.shared.changeActivity(next.session?.currentExercise) }
        UserDefaults.standard.set(next.comfort?.language, forKey: "littlelift.language")
    }

    func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { self.error = error.localizedDescription }
    }

    func start() throws {
        guard state.session == nil, let plan = state.plan else { throw WorkoutError.invalidState(L10n.s("Add a workout on your iPhone first.")) }
        var next = state; next.session = try WorkoutSession(plan: plan)
        if let minutes = next.comfort?.waterMinutes { next.session?.hydrationDue = Date().addingTimeInterval(Double(minutes * 60)) }
        try commit(next); prefill(); play(.start)
        Task { @MainActor in
            if let session = state.session { await WorkoutRuntime.shared.start(for: session) }
            await requestRestNotifications()
        }
    }

    func logSet() throws {
        guard LogActionGuard.allows(session: state.session, presentedSheet: presentedSheet != nil) else { return }
        var next = state
        guard var session = next.session else { return }
        try session.logSet(weight: draftWeight, reps: Int(draftReps.rounded()))
        if session.phase == .completed, next.comfort?.quietFeedback != true { session.feedback = FactualFeedback.message(for: session, previous: next.recent) }
        next.session = session; next.enqueueCompleted(); try commit(next)
        RhythmGuide.shared.stop()
        if session.phase == .completed { WorkoutRuntime.shared.finish(); notifications.cancel(); play(.success); retrySync() }
        else { play(.click); scheduleRest() }
        prefill()
    }

    enum TimedAction { case start, pause, resume, done, extend }
    func activityAction(_ action: TimedAction) throws {
        var next = state
        switch action {
        case .start: try next.session?.startActivity()
        case .pause: try next.session?.pauseActivity()
        case .resume: try next.session?.resumeActivity()
        case .done: try next.session?.completeActivity(source: .machine)
        case .extend: break
        }
        next.enqueueCompleted(); try commit(next)
        if next.session?.phase == .completed { WorkoutRuntime.shared.finish(); notifications.cancel(); retrySync() }
        prefill()
    }
    func activityReadings(distance: Double?, speed: Double?, incline: Double?) throws {
        var next = state; try next.session?.setActivityReadings(distance: distance, speed: speed, incline: incline); try commit(next)
    }
    func transitionAction(_ action: TimedAction) throws {
        var next = state
        switch action {
        case .pause: next.session?.pauseTransition()
        case .resume: next.session?.resumeTransition()
        case .extend: try next.session?.extendTransition()
        case .done: next.session?.skipTransition()
        case .start: break
        }
        try commit(next); prefill()
    }
    func chooseNext(_ id: UUID) throws {
        RhythmGuide.shared.stop()
        var next = state; try next.session?.chooseNext(id); try commit(next); prefill()
    }
    func deferExercise() throws {
        RhythmGuide.shared.stop()
        var next = state; try next.session?.deferCurrent(); try commit(next); prefill()
    }
    func substitute(_ id: UUID, future: Bool = false) throws {
        RhythmGuide.shared.stop()
        var next = state; try next.session?.substituteCurrent(with: id, proposeForFuture: future); try commit(next); prefill()
    }
    func skipExercise() throws {
        RhythmGuide.shared.stop()
        var next = state; try next.session?.skipExercise(reason: L10n.s("User chose to omit; no replacement prescribed."))
        next.enqueueCompleted(); try commit(next); prefill()
        if next.session?.phase == .completed { WorkoutRuntime.shared.finish(); notifications.cancel(); retrySync() }
    }
    func omitOptional(_ ids: [UUID]) throws {
        var next = state; try next.session?.omitOptional(ids); try commit(next); prefill()
    }
    func reverseAdjustment() throws {
        var next = state; try next.session?.undoAdjustment(); try commit(next); prefill()
    }
    func skipRest() throws {
        var next = state; next.session?.skipRest(); try commit(next)
        notifications.cancel(); prefill(); play(.click)
    }
    func extendRest() throws {
        var next = state; try next.session?.extendRest(); try commit(next); scheduleRest()
    }
    func restFinished(haptic: Bool) throws {
        var next = state
        guard next.session?.endRestIfDue() == true else { return }
        try commit(next); notifications.cancel(); prefill()
        if haptic, state.comfort?.restHaptics != false { play(.notification) }
    }
    func undo() throws {
        RhythmGuide.shared.stop()
        let undone = state.session?.entries.last
        var next = state; try next.session?.undoLastSet(); try commit(next)
        notifications.cancel(); prefill()
        if let undone {
            draftWeight = undone.weight; draftReps = Double(undone.reps)
        }
        play(.click)
    }
    func finishEarly() throws {
        RhythmGuide.shared.stop()
        var next = state; next.session?.finish(); next.enqueueCompleted(); try commit(next)
        WorkoutRuntime.shared.finish(); notifications.cancel(); play(.stop); retrySync()
    }
    func dismissSummary() throws {
        guard state.session?.phase == .completed else { return }
        // A second touch on the former Log button must not also dismiss Summary.
        if let completionUptime, ProcessInfo.processInfo.systemUptime - completionUptime < 0.8 { return }
        var next = state
        if next.session?.pendingEffort != nil { try next.session?.answerEffort(nil) }
        next.enqueueCompleted(); next.session = nil; try commit(next); retrySync()
    }
    func answerEffort(_ rating: Int?) throws {
        var next = state; try next.session?.answerEffort(rating)
        next.enqueueCompleted(); try commit(next)
        if next.session?.phase == .completed { retrySync() }
    }
    func waterReminder(snooze: Bool) throws {
        var next = state
        next.session?.hydrationDue = snooze ? Date().addingTimeInterval(Double((state.comfort?.waterMinutes ?? 15) * 60)) : nil
        try commit(next)
    }
    func sendMotion(_ url: URL, id: UUID) throws { try link.sendMotionFile(url, id: id) }
    func setHaptics(_ enabled: Bool) throws {
        var next = state; next.haptics = enabled; try commit(next)
        if !enabled { RhythmGuide.shared.stop() }
        scheduleRest()
    }
    func foreground() {
        Task { await WorkoutRuntime.shared.recover() }
        perform { try restFinished(haptic: false) }
        // Recover a future reminder after relaunch, including a first permission grant.
        scheduleRest()
        Task { await refreshNotificationStatus() }
        retrySync()
    }

    func refreshNotificationStatus() async {
        notificationStatus = await notifications.authorizationStatus()
    }

    func requestRestNotifications() async {
        do {
            try await notifications.askPermission()
            notificationIssue = nil
        } catch { notificationIssue = error.localizedDescription }
        await refreshNotificationStatus()
        // The first rest may have begun while the permission sheet was open.
        scheduleRest()
    }

    var restReminderMessage: String {
        if let notificationIssue { return L10n.s("Reminders unavailable: \(notificationIssue)") }
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return L10n.s("Rest reminders are allowed.")
        case .denied: return L10n.s("Rest reminders are off. You can allow them in the watch’s notification settings. The timer still works while Little Lift is open.")
        case .notDetermined: return L10n.s("Allow notifications for background rest reminders.")
        @unknown default: return L10n.s("Check rest reminders in the watch’s notification settings.")
        }
    }

    func retrySync() {
        for session in state.outbox {
            do { try link.enqueue(session) } catch { syncNote = error.localizedDescription }
        }
        link.requestSnapshot()
    }

    private func receive(_ message: SyncMessage) throws -> SyncMessage? {
        guard case .snapshot(let snapshot) = message else { return nil }
        var next = state
        let receipt = try SyncLogic.watchReply(to: snapshot, state: &next)
        try commit(next)
        if !next.haptics || next.comfort?.rhythmEnabled != true { RhythmGuide.shared.stop() }
        if next.motionOptIn != true { MotionCapture.shared.stop(status: "interrupted") }
        syncNote = next.plan == nil ? L10n.s("Connected. Add a workout in Little Lift on iPhone.") :
            (next.outbox.isEmpty ? L10n.s("Workout ready") : L10n.s("Workout ready. Logs waiting for iPhone confirmation."))
        return receipt
    }

    private func prefill() {
        guard let exercise = state.session?.currentExercise else { return }
        // Preserve the user's adjustment through subsequent sets of the same exercise.
        if let previous = state.session?.entries.last, previous.exerciseID == exercise.id {
            draftWeight = previous.weight; draftReps = Double(previous.reps)
        } else { draftWeight = exercise.weight; draftReps = Double(exercise.reps) }
    }
    func previousResult(for exercise: ExercisePlan, unit: WeightUnit) -> String? {
        guard let result = Progression.lastResult(for: exercise, unit: unit, sessions: state.recent) else { return nil }
        return "\(WorkoutSession.number(result.entry.weight)) \(unit.rawValue) × \(result.entry.reps)"
    }
    private func scheduleRest() {
        guard let deadline = state.session?.restUntil else { notifications.cancel(); return }
        notifications.schedule(deadline: deadline, sound: state.haptics && state.comfort?.restHaptics != false)
    }
    private func play(_ type: WKHapticType) { if state.haptics { WKInterfaceDevice.current().play(type) } }
    var summarySynced: Bool {
        guard let session = state.session else { return false }
        return session.isReadyForDelivery && !state.outbox.contains { $0.id == session.id }
    }
}

@MainActor
private final class RestNotifications {
    private let center = UNUserNotificationCenter.current()
    private let defaultsKey = "littlelift.restNotificationID"
    private var currentIdentifier = UserDefaults.standard.string(forKey: "littlelift.restNotificationID")

    func askPermission() async throws {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
    }
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
    func cancel() {
        if let identifier = currentIdentifier {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
        currentIdentifier = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
    func schedule(deadline: Date, sound: Bool) {
        cancel()
        let identifier = "littlelift.rest.\(UUID().uuidString)"
        currentIdentifier = identifier
        UserDefaults.standard.set(identifier, forKey: defaultsKey)
        Task { @MainActor in
            let settings = await center.notificationSettings()
            guard currentIdentifier == identifier, settings.authorizationStatus == .authorized,
                  deadline.timeIntervalSinceNow > 0 else { return }
            let content = UNMutableNotificationContent()
            content.title = L10n.s("Rest finished"); content.body = L10n.s("Your next set is ready.")
            if sound { content.sound = .default }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            // A cancellation may have happened while the notification was being registered.
            if currentIdentifier != identifier { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
        }
    }
}
