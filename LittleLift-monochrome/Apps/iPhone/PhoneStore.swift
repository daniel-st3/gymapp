import Foundation
import Observation

@MainActor @Observable
final class PhoneStore {
    static let shared = PhoneStore()
    private(set) var state = PhoneState()
    var error: String?
    var showingReviewQueue = false
    var openedReviewSessionID: UUID?
    @ObservationIgnored private var schedulingReviewIDs: Set<UUID> = []
    private(set) var motionRecordings: [MotionRecording] = []
    @ObservationIgnored private let motionRepository = MotionRepository(folder: URL.applicationSupportDirectory.appending(path: "LittleLiftMotion", directoryHint: .isDirectory))
    private(set) var storageBlocked = false
    private(set) var canRecoverFromBackup = false
    @ObservationIgnored private let reviewNotifications = ReviewNotifications()
    private(set) var syncMessage = L10n.s("Workouts sync when your watch is available.")
    private(set) var isSyncing = false
    private(set) var connectionDetails = L10n.s("Connecting…")
    @ObservationIgnored private let repository: FileRepository<PhoneState>
    @ObservationIgnored private let link = DeviceLink()

    private init() {
        let folder = URL.applicationSupportDirectory.appending(path: "LittleLift", directoryHint: .isDirectory)
        repository = FileRepository(url: folder.appending(path: "phone-v1.json"))
        do {
            try StorageSchema.validateHeader(at: repository.url)
            let loaded = try repository.load() ?? PhoneState()
            try StorageSchema.validate(loaded.storageVersion)
            canRecoverFromBackup = true
            try loaded.validateCorrections()
            try repository.checkpointBeforeUpgrade()
            if (loaded.storageVersion ?? 1) < 3 { try repository.checkpointBeforeUpgrade(suffix: "pre-build14") }
            state = loaded; canRecoverFromBackup = false
            UserDefaults.standard.set(state.comfort?.language, forKey: "littlelift.language")
        } catch {
            storageBlocked = true
            if error is DecodingError { canRecoverFromBackup = true }
            self.error = L10n.s("Stored data could not be read. It has not been overwritten. \(error.localizedDescription)")
        }
        link.onMessage = { [weak self] in try self?.receive($0) }
        link.onReady = { [weak self] in self?.sendToWatch() }
        link.onStatus = { [weak self] in self?.syncMessage = $0 }
        link.onBusy = { [weak self] in self?.isSyncing = $0 }
        link.onDetails = { [weak self] in self?.connectionDetails = $0 }
        link.onMotionFile = { [weak self] data in
            guard let self else { return }; try self.motionRepository.receive(data); self.loadMotion()
        }
        link.activate()
        reviewNotifications.onOpen = { [weak self] id in
            guard let self else { return }
            openedReviewSessionID = id
            showingReviewQueue = true
        }
        refreshReviewNotifications()
        #if DEBUG
        // The explicit simulator launcher uses a generic demo only for an empty
        // install. It never replaces an existing plan or personal training data.
        if !storageBlocked, state.plan == nil, ProcessInfo.processInfo.arguments.contains("--littlelift-demo") {
            do { try importPlan(PlanImport.example) } catch { self.error = error.localizedDescription }
        }
        #endif
    }

    private func commit(_ candidate: PhoneState) throws {
        var next = candidate; next.storageVersion = 3
        guard !storageBlocked else { throw WorkoutError.invalidState(L10n.s("Stored data could not be read. Restart after restoring your backup.")) }
        try repository.save(next)
        state = next
        UserDefaults.standard.set(next.comfort?.language, forKey: "littlelift.language")
    }

    func correctSet(sessionID: UUID, setID: UUID, expectedWeight: Double, expectedReps: Int, weight: Double, reps: Int, reason: String) throws {
        var next = state
        try next.correctSet(sessionID: sessionID, setID: setID, expectedWeight: expectedWeight, expectedReps: expectedReps, weight: weight, reps: reps, reason: reason)
        try commit(next)
    }
    func restoreBackup(_ preview: BackupRestorePreview) throws {
        var next = state; try next.restore(preview)
        // Keep a complete local checkpoint before every explicit restoration.
        let checkpoint = repository.url.deletingLastPathComponent().appending(path: "before-restore-\(UUID().uuidString).json")
        if storageBlocked {
            guard canRecoverFromBackup else {
                throw WorkoutError.invalidState(L10n.s("Update Little Lift to read this storage version. Recovery cannot replace a newer format."))
            }
            try repository.saveRecovery(next, checkpoint: checkpoint)
            state = next; storageBlocked = false; canRecoverFromBackup = false
            UserDefaults.standard.set(next.comfort?.language, forKey: "littlelift.language")
        } else {
            try FileRepository<PhoneState>(url: checkpoint).save(state)
            try commit(next)
        }
        if preview.preferencesIncluded { sendToWatch() }
    }

    func importPlan(_ text: String) throws {
        try acceptImportedPlan(PlanImport.parse(text))
    }
    func acceptImportedPlan(_ plan: WorkoutPlan) throws {
        try saveWorkout(plan, useToday: true)
    }
    func prepareChatHandoff(request: String) throws -> ChatHandoff {
        var next = state; let packet = try next.prepareChatHandoff(request: request)
        try commit(next); return packet
    }
    func acceptChatReply(_ reply: ChatWorkoutReply, editedPlan: WorkoutPlan, useToday: Bool) throws {
        var next = state; try next.acceptChatReply(reply, editedPlan: editedPlan, useToday: useToday)
        try commit(next)
        if useToday { sendToWatch() }
    }
    func proposeImport(_ text: String) throws {
        var next = state
        try next.propose(TrainingReview(analysis: L10n.s("Review this imported workout and what it will collect before accepting."), plan: PlanImport.parse(text)))
        try commit(next)
    }
    @discardableResult func saveReview(_ text: String) throws -> Bool {
        var next = state
        let isCheck = try next.receiveConnectionCheck(text)
        if !isCheck { try next.receiveReview(text) }
        try commit(next); return isCheck
    }
    func prepareConnectionCheck() throws -> String {
        var next = state; let prompt = try next.beginConnectionCheck(); try commit(next); return prompt
    }
    func cancelConnectionCheck() throws {
        var next = state; next.cancelConnectionCheck(); try commit(next)
    }
    func acceptReview() throws {
        var next = state; try next.acceptReview()
        try commit(next); sendToWatch()
    }
    func discardReview() throws { var next = state; next.discardReview(); try commit(next) }
    func stageUnlinkedReview(_ id: UUID) throws {
        guard let saved = state.unlinkedCoachReviews?.first(where: { $0.id == id }) else { throw WorkoutError.invalidState(L10n.s("This response is no longer available. Reopen workout reviews.")) }
        if let date = state.unlinkedCoachReviewsOutdatedAt, saved.savedAt <= date {
            throw WorkoutError.invalidState(L10n.s("Workout evidence changed. Share the updated report before using this older proposal."))
        }
        var next = state; try next.propose(saved.response); try commit(next)
    }
    func stageSavedReview(_ id: UUID) throws {
        var next = state; try next.stageSavedReview(for: id); try commit(next)
    }
    func setComfort(_ value: ComfortPreferences) throws { try value.validate(); var value = value; value.revision = UUID(); var next = state; next.comfort = value; try commit(next); sendToWatch() }
    func setWeeklyGoal(days: Int, paused: Bool) throws {
        var next = state; var habit = next.weeklyHabit ?? WeeklyHabit(timeZone: TimeZone.current.identifier, goals: [])
        try habit.schedule(days: days, paused: paused, now: Date()); next.weeklyHabit = habit; try commit(next)
    }
    func completeOnboarding(_ step: String) throws {
        var next = state; next.onboardingSteps = Array(Set((next.onboardingSteps ?? []) + [step])); try commit(next)
    }
    func saveContext(profile: Bool, history: Bool, equipment: String) throws {
        guard equipment.count <= 2000 else { throw WorkoutError.invalidInput(L10n.s("Keep equipment notes below 2,000 characters.")) }
        var next = state; next.contextProfileApproved = profile; next.contextHistoryApproved = history; next.equipmentContext = equipment; try commit(next)
    }
    func setProfile(_ text: String) throws {
        guard text.count <= 12_000 else { throw WorkoutError.invalidInput(L10n.s("Keep the training profile below 12,000 characters.")) }
        var next = state; next.profile = text; try commit(next)
    }
    func setMode(_ mode: ConnectionMode) throws { var next = state; next.mode = mode; try commit(next) }

    func prepareReview() throws -> String {
        if state.sessions.isEmpty { return reviewPrompt }
        var next = state; let ticket = try next.beginReview(sessionID: next.selectedReviewSessionID)
        next.selectedReviewSessionID = nil
        let prompt = try next.prompt(for: ticket); try commit(next); return prompt
    }
    func selectReview(_ id: UUID) throws {
        var next = state; next.selectedReviewSessionID = id; try commit(next)
    }
    func refreshReviewStatus() {
        guard !storageBlocked else { return }
        do { var next = state; next.expireReviewAttempts(); if next != state { try commit(next) } }
        catch { self.error = error.localizedDescription }
    }
    func endReview(_ id: UUID, cancelled: Bool, detail: String) throws {
        var next = state; try next.endReview(id, cancelled: cancelled, detail: detail); try commit(next)
    }
    func enableReviewNotifications(_ enabled: Bool) async {
        do {
            if enabled { try await reviewNotifications.requestPermission() }
            var next = state; next.reviewNotificationsEnabled = enabled; try commit(next)
            if enabled { refreshReviewNotifications() } else { await reviewNotifications.cancelPending() }
        } catch { self.error = error.localizedDescription }
    }
    private func refreshReviewNotifications() {
        guard state.reviewNotificationsEnabled == true else { return }
        for job in state.reviewQueue where job.status == .queued && job.notified != true {
            guard schedulingReviewIDs.insert(job.id).inserted else { continue }
            Task { @MainActor in
                defer { schedulingReviewIDs.remove(job.id) }
                do {
                    guard state.reviewNotificationsEnabled == true else { return }
                    try await reviewNotifications.schedule(sessionID: job.id)
                    var next = state
                    if let i = next.reviewJobs?.firstIndex(where: { $0.id == job.id }) { next.reviewJobs?[i].notified = true; try commit(next) }
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
        }
    }
    func loadMotion() {
        do { motionRecordings = try motionRepository.recordings() } catch { self.error = error.localizedDescription }
    }
    func setMotionOptIn(_ enabled: Bool) throws { var next = state; next.motionOptIn = enabled; try commit(next); sendToWatch() }
    func setMotionExercise(_ exercise: MotionExercise) throws { var next = state; next.motionExercise = exercise; try commit(next); sendToWatch() }
    func saveMotion(_ recording: MotionRecording) throws { try motionRepository.save(recording); loadMotion() }
    func deleteMotion(_ id: UUID) throws { try motionRepository.delete(id); loadMotion() }
    func setDoubleTap(_ enabled: Bool) throws { var next = state; next.doubleTapEnabled = enabled; try commit(next); sendToWatch() }
    func setTimeBudget(_ budget: TimeBudget?) throws {
        guard var plan = state.plan else { throw WorkoutError.invalidState(L10n.s("Choose a workout first.")) }
        try budget?.validate(); if plan.timeBudget == budget { return }; plan.timeBudget = budget; plan.id = UUID(); try plan.validate()
        var next = state; next.plan = plan; try commit(next); sendToWatch()
    }
    func saveRoutine(_ plan: WorkoutPlan, replacing id: UUID? = nil) throws {
        try saveWorkout(plan, replacing: id, useToday: false)
    }
    func saveWorkout(_ plan: WorkoutPlan, replacing id: UUID? = nil, useToday: Bool) throws {
        var next = state; try next.saveWorkout(plan, replacing: id, useToday: useToday)
        try commit(next)
        if useToday { sendToWatch() }
    }
    func chooseRoutine(_ routine: Routine) throws { try acceptImportedPlan(routine.plan) }
    func scheduleRoutine(_ id: UUID?, weekday: Int) throws {
        var next = state; try next.scheduleRoutine(id, weekday: weekday); try commit(next)
    }
    func importHistory(_ records: [HistoricalWorkout]) throws {
        var next = state; try next.importHistory(records); try commit(next)
    }
    func sendToWatch(acknowledging id: UUID? = nil) {
        // A blocked store contains only the in-memory fallback. Publishing that
        // fallback would clear the Watch's saved plan while phone recovery waits.
        guard !storageBlocked else { return }
        do {
            try link.publish(SyncLogic.snapshot(from: state, acknowledging: id))
        } catch { syncMessage = L10n.s("Saved on iPhone. \(error.localizedDescription)") }
    }
    private func receive(_ message: SyncMessage) throws -> SyncMessage? {
        guard !storageBlocked else { throw WorkoutError.invalidState(L10n.s("The iPhone could not read its stored workouts. Your watch data is still saved.")) }
        if case .planReceived(let id) = message, id == state.plan?.id {
            var next = state; next.recordWatchReceipt(id)
            if next != state { try commit(next) }
            syncMessage = L10n.s("Workout received on watch.")
            return nil
        }
        var next = state
        let response = try SyncLogic.phoneReply(to: message, state: &next)
        if next != state { try commit(next); refreshReviewNotifications() }
        return response
    }
    var reviewPrompt: String { PlanImport.reviewPrompt(profile: state.contextExport(), sessions: []) }
}
