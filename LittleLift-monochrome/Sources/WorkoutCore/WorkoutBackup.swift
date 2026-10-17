import Foundation

/// Portable, explicit user export. No executable requests, credentials, device
/// pairing, HealthKit data or raw experimental motion recordings are included.
public struct WorkoutBackup: Codable, Equatable, Sendable {
    public let format: String
    public let version: Int
    public let createdAt: Date
    public let state: PhoneState
    public static let maximumBytes = 20_000_000

    public init(state: PhoneState, now: Date = Date()) throws {
        format = "littlelift.workout-backup"; version = 1; createdAt = now; self.state = state
        try validate()
    }
    public func encoded() throws -> Data {
        try validate()
        let data = try FileRepository<WorkoutBackup>.encoder().encode(self)
        guard data.count <= Self.maximumBytes else { throw Self.invalid() }
        return data
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw invalid() }
        let backup: Self
        do { backup = try FileRepository<Self>.decoder().decode(Self.self, from: data) }
        catch { throw WorkoutError.invalidInput(L10n.s("Choose a Little Lift backup. A workout import or damaged file cannot be restored as a backup.")) }
        try backup.validate(); return backup
    }
    private static func invalid() -> WorkoutError {
        .invalidInput(L10n.s("This backup is invalid or exceeds its supported limits. No saved records were changed."))
    }
    public func validate() throws {
        guard format == "littlelift.workout-backup", version == 1, InputBoundary.validDate(createdAt) else {
            throw WorkoutError.invalidInput(L10n.s("This backup format is not supported. Update Little Lift before restoring it."))
        }
        try Self.validate(state)
    }
    public static func validate(_ state: PhoneState) throws {
        try StorageSchema.validate(state.storageVersion)
        guard state.sessions.count <= 5000, Set(state.sessions.map(\.id)).count == state.sessions.count,
              state.routineLibrary.count <= 100, Set(state.routineLibrary.map(\.id)).count == state.routineLibrary.count,
              state.externalHistory.count <= 5000, Set(state.externalHistory.map(\.id)).count == state.externalHistory.count,
              state.profile.count <= 12_000, (state.equipmentContext?.count ?? 0) <= 2000,
              state.weeklySchedule.count <= 7, Set(state.weeklySchedule.map(\.weekday)).count == state.weeklySchedule.count,
              state.reviewQueue.count <= 5000, Set(state.reviewQueue.map(\.id)).count == state.reviewQueue.count,
              (state.unlinkedCoachReviews?.count ?? 0) <= 5000,
              (state.onboardingSteps?.count ?? 0) <= 20, state.onboardingSteps?.allSatisfy({ $0.count <= 80 }) ?? true else { throw invalid() }
        try state.plan?.validate(); try state.comfort?.validate()
        for session in state.sessions { try session.validateCompleted() }
        try state.validateCorrections()
        for record in state.externalHistory { try record.validate() }
        for routine in state.routineLibrary {
            try routine.plan.validate()
            guard routine.previousVersions.count <= 100 else { throw invalid() }
            for version in routine.previousVersions { try version.validate() }
        }
        for slot in state.weeklySchedule {
            guard (1...7).contains(slot.weekday), state.routineLibrary.contains(where: { $0.id == slot.routineID }) else { throw invalid() }
        }
        func review(_ value: TrainingReview) throws {
            guard value.analysis.count <= 12_000 else { throw invalid() }
            try value.plan.validate()
        }
        if let value = state.review { try review(value) }
        let ids = Set(state.sessions.map(\.id))
        for job in state.reviewQueue {
            guard ids.contains(job.id), (job.detail?.count ?? 0) <= 2000,
                  [job.startedAt, job.receivedAt, job.outdatedAt].compactMap({ $0 }).allSatisfy(InputBoundary.validDate),
                  (job.previousResults?.count ?? 0) <= 100 else { throw invalid() }
            if let value = job.result { try review(value) }
            for value in job.previousResults ?? [] { try review(value) }
        }
        let unlinked = state.unlinkedCoachReviews ?? []
        guard Set(unlinked.map(\.id)).count == unlinked.count else { throw invalid() }
        for saved in unlinked { guard InputBoundary.validDate(saved.savedAt) else { throw invalid() }; try review(saved.response) }
        if let habit = state.weeklyHabit {
            guard TimeZone(identifier: habit.timeZone) != nil, habit.goals.count <= 520,
                  Set(habit.goals.map(\.id)).count == habit.goals.count,
                  habit.goals.allSatisfy({ (1...7).contains($0.minimumDays) && InputBoundary.validDate($0.effectiveWeek) }) else { throw invalid() }
        }
        if let receipt = state.lastWatchReceipt { guard InputBoundary.validDate(receipt.receivedAt) else { throw invalid() } }
        if let date = state.unlinkedCoachReviewsOutdatedAt { guard InputBoundary.validDate(date) else { throw invalid() } }
    }
}

public struct BackupRestorePreview: Sendable {
    public let original: PhoneState
    public let restored: PhoneState
    public let workoutsAdded: Int
    public let routinesAdded: Int
    public let importedAdded: Int
    public let correctionsAdded: Int
    public let conflicts: [String]
    public let unchanged: Int
    public let preferencesIncluded: Bool

    /// Merge only. Conflicting IDs stay local and are listed. An older archive
    /// never rolls back a correction, replaces Today or starts a model request.
    public init(backup: WorkoutBackup, current: PhoneState, includePreferences: Bool, now: Date = Date()) throws {
        try backup.validate(); try WorkoutBackup.validate(current)
        original = current; preferencesIncluded = includePreferences
        let incoming = backup.state
        var next = current, conflicts: [String] = [], unchanged = 0
        var acceptedIDs = Set<UUID>()
        for record in incoming.sessions {
            if let old = next.sessions.first(where: { $0.id == record.id }) {
                if old == record { acceptedIDs.insert(record.id); unchanged += 1 }
                else { conflicts.append(L10n.s("Workout conflict · \(record.plan.title) [\(record.id.uuidString)]")) }
            } else { next.sessions.append(record); acceptedIDs.insert(record.id) }
        }
        next.sessions.sort { $0.startedAt > $1.startedAt }
        for id in acceptedIDs {
            let local = next.correctionLog.filter { $0.sessionID == id }
            let other = incoming.correctionLog.filter { $0.sessionID == id }
            if other.starts(with: local) {
                if other.count > local.count { next.setCorrections = next.correctionLog + Array(other.dropFirst(local.count)) }
            } else if !local.starts(with: other) {
                conflicts.append(L10n.s("Correction conflict · \(incoming.sessions.first { $0.id == id }!.plan.title) [\(id.uuidString)]"))
            }
        }
        var routines = next.routineLibrary
        for routine in incoming.routineLibrary {
            if let old = routines.first(where: { $0.id == routine.id }) {
                if old != routine { conflicts.append(L10n.s("Routine conflict · \(routine.plan.title) [\(routine.id.uuidString)]")) }
                else { unchanged += 1 }
            } else { routines.append(routine) }
        }
        // The archived Today plan is available as a routine, never activated.
        if let plan = incoming.plan, !routines.contains(where: { $0.plan == plan || $0.previousVersions.contains(plan) }) {
            routines.append(Routine(plan: plan))
        }
        next.routines = routines
        var imported = next.externalHistory
        for record in incoming.externalHistory {
            if let old = imported.first(where: { $0.id == record.id }) {
                if old != record { conflicts.append(L10n.s("Imported record conflict · \(record.title) [\(record.id.uuidString)]")) }
                else { unchanged += 1 }
            } else { imported.append(record) }
        }
        next.importedHistory = imported.sorted { ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast) }
        var jobs = next.reviewQueue
        for job in incoming.reviewQueue where acceptedIDs.contains(job.id) {
            if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                var archive = jobs[index].previousResults ?? []
                for value in (job.previousResults ?? []) + [job.result].compactMap({ $0 }) where value != jobs[index].result && !archive.contains(value) { archive.append(value) }
                if !archive.isEmpty { jobs[index].previousResults = archive }
            } else {
                var restored = job
                // Restoring bytes never restores an authorization or an attempt.
                restored.attemptID = nil; restored.startedAt = nil; restored.notified = true
                restored.status = restored.result == nil ? .cancelled : .received
                if restored.result != nil { restored.outdatedAt = now }
                restored.detail = L10n.s("Restored from backup. Run a new review only if you choose.")
                jobs.append(restored)
            }
        }
        next.reviewJobs = jobs
        var unlinked = next.unlinkedCoachReviews ?? []
        for item in incoming.unlinkedCoachReviews ?? [] {
            if let old = unlinked.first(where: { $0.id == item.id }) {
                if old != item { conflicts.append(L10n.s("Coach response conflict · \(item.response.plan.title + " [" + item.id.uuidString + "]")")) }
            } else if !unlinked.contains(where: { $0.response == item.response }) { unlinked.append(item) }
        }
        if let proposal = incoming.review, !jobs.contains(where: { $0.result == proposal }), !unlinked.contains(where: { $0.response == proposal }) {
            unlinked.append(UnlinkedCoachReview(id: UUID(), response: proposal, savedAt: backup.createdAt))
        }
        next.unlinkedCoachReviews = unlinked
        if includePreferences {
            next.profile = incoming.profile; next.equipmentContext = incoming.equipmentContext
            next.comfort = incoming.comfort; next.weeklyHabit = incoming.weeklyHabit
            next.mode = incoming.mode; next.doubleTapEnabled = incoming.doubleTapEnabled
            next.schedule = incoming.schedule
            // Sharing and experimental permissions remain explicit on this device.
        }
        // New evidence can change comparisons. Preserve results but invalidate
        // their assumptions and running receipts, including conflicting imports.
        if next.sessions != current.sessions || next.correctionLog != current.correctionLog || next.externalHistory != current.externalHistory || next.profile != current.profile || next.equipmentContext != current.equipmentContext {
            next.invalidateCoachEvidence(now: now)
        }
        next.storageVersion = 3
        try WorkoutBackup.validate(next)
        restored = next
        workoutsAdded = next.sessions.count - current.sessions.count
        routinesAdded = next.routineLibrary.count - current.routineLibrary.count
        importedAdded = next.externalHistory.count - current.externalHistory.count
        correctionsAdded = next.correctionLog.count - current.correctionLog.count
        self.conflicts = conflicts; self.unchanged = unchanged
    }
}

public struct WatchPlanReceipt: Codable, Equatable, Sendable {
    public let planID: UUID
    public let receivedAt: Date
    public init(planID: UUID, receivedAt: Date) { self.planID = planID; self.receivedAt = receivedAt }
}
extension PhoneState {
    public var todayReceivedOnWatch: Bool { plan.map { $0.id == lastWatchReceipt?.planID } ?? false }
    public mutating func recordWatchReceipt(_ id: UUID, now: Date = Date()) {
        guard id == plan?.id, lastWatchReceipt?.planID != id else { return }
        lastWatchReceipt = WatchPlanReceipt(planID: id, receivedAt: now)
    }
    public mutating func restore(_ preview: BackupRestorePreview) throws {
        guard self == preview.original else {
            throw WorkoutError.invalidState(L10n.s("New data arrived during the preview. Preview this backup again before restoring."))
        }
        self = preview.restored
    }
}
