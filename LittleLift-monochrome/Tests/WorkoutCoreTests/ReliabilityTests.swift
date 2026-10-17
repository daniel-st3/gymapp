import Foundation
import Testing
@testable import WorkoutCore

struct ReliabilityTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    func completed() throws -> WorkoutSession {
        let exercise = ExercisePlan(name: "Generic row", sets: 2, reps: 10, weight: 20, restSeconds: 60,
                                   comparisonID: "row-a", loadConvention: .machineStack)
        let plan = WorkoutPlan(title: "Generic workout", unit: .kg, exercises: [exercise])
        var session = try WorkoutSession(plan: plan, now: start)
        try session.logSet(weight: 80, reps: 9, now: start.addingTimeInterval(30), uptime: 100)
        session.skipRest(now: start.addingTimeInterval(90))
        try session.logSet(weight: 20, reps: 8, now: start.addingTimeInterval(120), uptime: 190)
        return session
    }
    func state() throws -> PhoneState {
        var state = PhoneState(); let session = try completed(); try state.receive(session)
        state.plan = session.plan; try state.saveRoutine(session.plan)
        return state
    }
    func correct(_ state: inout PhoneState, weight: Double = 60, reps: Int = 10, now: Date? = nil) throws {
        let session = state.effectiveSessions[0], set = session.entries[0]
        try state.correctSet(sessionID: session.id, setID: set.id, expectedWeight: set.weight, expectedReps: set.reps,
                             weight: weight, reps: reps, reason: "Entry typo", now: now ?? start.addingTimeInterval(200))
    }
    @Test func correctionPreservesOriginalDeliveryEventsAndRecomputesEvidence() throws {
        var state = try state(); let original = state.sessions[0]
        let originalBytes = try FileRepository<WorkoutSession>.encoder().encode(original)
        try correct(&state)
        #expect(try FileRepository<WorkoutSession>.encoder().encode(state.sessions[0]) == originalBytes)
        let revised = state.effectiveSessions[0]
        #expect(revised.entries[0].weight == 60 && revised.entries[0].reps == 10)
        #expect(revised.entries[0].completedAt == original.entries[0].completedAt)
        #expect(revised.loggingInterval(before: revised.entries[1]) == original.loggingInterval(before: original.entries[1]))
        #expect(revised.plan == original.plan && revised.endedAt == original.endedAt)
        #expect(revised.report().contains("CORRECTED ON IPHONE"))
        #expect(state.localReview(for: original.id)?.comparisons[0].entry.weight == 60)
        #expect(state.contextExport().contains("CORRECTED ON IPHONE"))
        let analytics = TrainingAnalytics(state: state, now: start.addingTimeInterval(300))
        #expect(analytics.repCount == 18 && analytics.exercises[0].results[0].entries[0].weight == 60)
        let reply = try SyncLogic.phoneReply(to: .completed(original), state: &state)
        #expect(reply != nil && state.sessions.count == 1 && state.effectiveSessions[0].entries[0].weight == 60)
        #expect(throws: (any Error).self) { try state.receive(revised) }
        let restored = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(state))
        try restored.validateCorrections()
        #expect(restored.effectiveSessions == state.effectiveSessions)
    }
    @Test func correctionAuditCanReturnToOriginalAndRejectsStaleOrInvalidEdits() throws {
        var state = try state(); let original = state.sessions[0]
        try correct(&state)
        let checkpoint = state
        #expect(throws: (any Error).self) {
            try state.correctSet(sessionID: original.id, setID: original.entries[0].id, expectedWeight: 80, expectedReps: 9,
                                 weight: 30, reps: 10, reason: "Stale", now: start.addingTimeInterval(250))
        }
        #expect(state == checkpoint)
        for invalid in [Double.nan, Double.infinity, -1, 1001] {
            #expect(throws: (any Error).self) { try correct(&state, weight: invalid) }
            #expect(state == checkpoint)
        }
        #expect(throws: (any Error).self) { try correct(&state, reps: 0) }
        #expect(throws: (any Error).self) { try correct(&state, now: start) }
        try correct(&state, weight: 80, reps: 9, now: start.addingTimeInterval(300))
        #expect(state.effectiveSessions[0].entries == original.entries)
        #expect(state.correctionLog.count == 2 && state.sessions[0] == original)
    }
    @Test func correctionRevokesAttemptsAndMarksSavedFeedbackUntilFreshResult() throws {
        var state = try state()
        let ticket = try state.beginReview(now: start.addingTimeInterval(150))
        let delayed = try response(ticket, plan: state.plan!)
        try correct(&state)
        #expect(throws: (any Error).self) { try state.receiveReview(delayed, now: start.addingTimeInterval(210)) }
        let retry = try state.beginReview(now: start.addingTimeInterval(220))
        let prompt = try state.prompt(for: retry)
        #expect(prompt.contains("CORRECTED ON IPHONE"))
        try state.receiveReview(try response(retry, plan: state.plan!), now: start.addingTimeInterval(230))
        let saved = state.reviewQueue[0].result
        try correct(&state, weight: 55, now: start.addingTimeInterval(240))
        #expect(state.review == nil && state.reviewQueue[0].result == saved && state.reviewQueue[0].outdatedAt != nil)
        #expect(throws: (any Error).self) { try state.stageSavedReview(for: state.sessions[0].id) }
        let fresh = try state.beginReview(now: start.addingTimeInterval(250))
        try state.receiveReview(try response(fresh, plan: state.plan!), now: start.addingTimeInterval(260))
        #expect(state.reviewQueue[0].previousResults == [saved!])
        #expect(state.reviewQueue[0].outdatedAt == nil)
    }
    func response(_ ticket: ReviewTicket, plan: WorkoutPlan) throws -> String {
        let review = TrainingReview(analysis: "Generic response", plan: plan)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(review)) as! [String: Any]
        object["reviewSessionID"] = ticket.sessionID.uuidString; object["reviewAttemptID"] = ticket.attemptID.uuidString
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    @Test func backupRoundTripPreservesArchivesAndDoesNotActivatePlanOrModel() throws {
        var source = try state(); try correct(&source)
        source.profile = "Generic preferences"
        _ = try source.beginReview(now: start.addingTimeInterval(300))
        let bytes = try WorkoutBackup(state: source, now: start.addingTimeInterval(310)).encoded()
        let backup = try WorkoutBackup.decode(bytes)
        #expect(backup.state == source)
        var destination = PhoneState()
        let preview = try BackupRestorePreview(backup: backup, current: destination, includePreferences: true)
        #expect(preview.workoutsAdded == 1 && preview.correctionsAdded == 1 && preview.conflicts.isEmpty)
        try destination.restore(preview)
        #expect(destination.plan == nil && destination.profile == source.profile)
        #expect(destination.sessions == source.sessions && destination.effectiveSessions == source.effectiveSessions)
        #expect(destination.reviewQueue[0].attemptID == nil && destination.reviewQueue[0].status != .running)
        #expect(destination.reviewNotificationsEnabled == nil && destination.motionOptIn == nil)
        let again = try BackupRestorePreview(backup: backup, current: destination, includePreferences: false)
        #expect(again.workoutsAdded == 0 && again.routinesAdded == 0 && again.correctionsAdded == 0)
        try destination.restore(again)
        #expect(destination.sessions.count == 1 && destination.correctionLog.count == 1)
    }
    @Test func oldBackupCannotRollBackCorrectionsOrOverwriteToday() throws {
        var current = try state(); let backup = try WorkoutBackup(state: current)
        try correct(&current)
        let preview = try BackupRestorePreview(backup: backup, current: current, includePreferences: false)
        try current.restore(preview)
        #expect(current.effectiveSessions[0].entries[0].weight == 60 && current.correctionLog.count == 1)
        #expect(current.plan == backup.state.plan)
    }
    @Test func divergentCorrectionsAreShownAndCurrentBranchWins() throws {
        var current = try state(), incoming = current
        try correct(&current, weight: 60); try correct(&incoming, weight: 55)
        let preview = try BackupRestorePreview(backup: WorkoutBackup(state: incoming), current: current, includePreferences: false)
        #expect(preview.conflicts.count == 1 && preview.correctionsAdded == 0)
        try current.restore(preview)
        #expect(current.effectiveSessions[0].entries[0].weight == 60)
    }
    @Test func repeatRestoreDoesNotDiscardCurrentProposalOrRestartReviews() throws {
        var current = try state()
        current.review = TrainingReview(analysis: "Pending proposal", plan: current.plan!)
        let archive = try WorkoutBackup(state: current)
        let preview = try BackupRestorePreview(backup: archive, current: current, includePreferences: false)
        try current.restore(preview)
        #expect(current.review == archive.state.review)
        let again = try BackupRestorePreview(backup: archive, current: current, includePreferences: false)
        try current.restore(again)
        #expect(current.review == archive.state.review && current.unlinkedCoachReviews?.count == 1)
        #expect(current.reviewQueue == archive.state.reviewQueue)
    }
    @Test func invalidBackupAndConcurrentReceiveDoNotMutateState() throws {
        var current = try state()
        let backup = try WorkoutBackup(state: current), original = current
        var object = try JSONSerialization.jsonObject(with: backup.encoded()) as! [String: Any]
        object["version"] = 99
        #expect(throws: (any Error).self) { try WorkoutBackup.decode(JSONSerialization.data(withJSONObject: object)) }
        #expect(throws: (any Error).self) { try WorkoutBackup.decode(Data(repeating: 32, count: WorkoutBackup.maximumBytes + 1)) }
        #expect(throws: (any Error).self) { try WorkoutBackup.decode(Data("{\"format\":\"littlelift.workout-backup\"}".utf8)) }
        let preview = try BackupRestorePreview(backup: backup, current: current, includePreferences: true)
        current.profile = "New edit while preview was open"
        let changed = current
        #expect(throws: (any Error).self) { try current.restore(preview) }
        #expect(current == changed && current.sessions == original.sessions)
    }
    @Test func backupRejectsDuplicateIDsOrForgedCorrectionChains() throws {
        var state = try state()
        state.sessions.append(state.sessions[0])
        #expect(throws: (any Error).self) { try WorkoutBackup(state: state) }
        state.sessions.removeLast(); try correct(&state)
        var data = try JSONSerialization.jsonObject(with: FileRepository<PhoneState>.encoder().encode(state)) as! [String: Any]
        var changes = data["setCorrections"] as! [[String: Any]]; changes[0]["previousWeight"] = 999; data["setCorrections"] = changes
        let forged = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: JSONSerialization.data(withJSONObject: data))
        #expect(throws: (any Error).self) { try WorkoutBackup(state: forged) }
    }
    @Test func explicitRecoveryPreservesUnreadableBytesAndNeverOverwritesCheckpoint() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileRepository<PhoneState>(url: folder.appendingPathComponent("state.json"))
        let bad = Data("{damaged original".utf8), checkpoint = folder.appendingPathComponent("before.json")
        try bad.write(to: repository.url)
        let recovered = try state()
        try repository.saveRecovery(recovered, checkpoint: checkpoint)
        #expect(try Data(contentsOf: checkpoint) == bad)
        #expect(try repository.load() == recovered)
        let saved = try Data(contentsOf: repository.url)
        #expect(throws: (any Error).self) { try repository.saveRecovery(PhoneState(), checkpoint: checkpoint) }
        #expect(try Data(contentsOf: repository.url) == saved)
    }
    @Test func futureStorageHeaderBlocksRecoveryEvenWhenPayloadCannotDecode() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        for version in ["4", "\"unknown\"", "true"] {
            try Data("{\"storageVersion\":\(version),\"sessions\":\"future representation\"}".utf8).write(to: url)
            #expect(throws: (any Error).self) { try StorageSchema.validateHeader(at: url) }
        }
        try Data("{\"storageVersion\":3,\"sessions\":[]}".utf8).write(to: url)
        try StorageSchema.validateHeader(at: url)
    }
    @Test func legacyStateAndConfirmedPlanReceiptsRemainCompatible() throws {
        var state = try state()
        #expect(state.setCorrections == nil && state.effectiveSessions == state.sessions)
        #expect(!state.todayReceivedOnWatch)
        state.recordWatchReceipt(UUID()); #expect(!state.todayReceivedOnWatch)
        state.recordWatchReceipt(state.plan!.id, now: start)
        #expect(state.todayReceivedOnWatch)
        let receipt = state.lastWatchReceipt
        state.recordWatchReceipt(state.plan!.id, now: start.addingTimeInterval(60)); #expect(state.lastWatchReceipt == receipt)
        state.plan?.id = UUID(); #expect(!state.todayReceivedOnWatch)
        let decoded = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(state))
        #expect(decoded == state)
    }
}
