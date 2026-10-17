import Foundation

/// An append-only correction. The Watch's original delivery remains byte-for-byte
/// comparable; only phone presentation and analysis use the corrected projection.
public struct SetCorrection: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let setID: UUID
    public let previousWeight: Double
    public let previousReps: Int
    public let weight: Double
    public let reps: Int
    public let recordedAt: Date
    public let reason: String
}

extension PhoneState {
    public var correctionLog: [SetCorrection] { setCorrections ?? [] }
    public var effectiveSessions: [WorkoutSession] {
        let grouped = Dictionary(grouping: correctionLog, by: \.sessionID)
        return sessions.map { $0.applying(grouped[$0.id] ?? []) }
    }
    public func effectiveSession(_ id: UUID) -> WorkoutSession? {
        sessions.first { $0.id == id }?.applying(correctionLog.filter { $0.sessionID == id })
    }
    public func validateCorrections() throws {
        try coachConnectionCheck?.validate()
        guard correctionLog.count <= 20_000, Set(correctionLog.map(\.id)).count == correctionLog.count else {
            throw WorkoutError.invalidInput(L10n.s("The correction archive is invalid or too large."))
        }
        let originals = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, changes) in Dictionary(grouping: correctionLog, by: \.sessionID) {
            guard let original = originals[id], changes.count <= 1000 else {
                throw WorkoutError.invalidInput(L10n.s("A correction has no original workout."))
            }
            guard Set(original.entries.map(\.id)).count == original.entries.count else {
                throw WorkoutError.invalidInput(L10n.s("A correction has no original workout."))
            }
            var values = Dictionary(uniqueKeysWithValues: original.entries.map { ($0.id, $0) })
            var previousDate = original.endedAt ?? .distantFuture
            for change in changes {
                guard let old = values[change.setID], old.weight == change.previousWeight, old.reps == change.previousReps,
                      change.weight.isFinite, (0...1000).contains(change.weight), (1...200).contains(change.reps),
                      InputBoundary.validDate(change.recordedAt), change.recordedAt >= previousDate,
                      !change.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, change.reason.count <= 240 else {
                    throw WorkoutError.invalidInput(L10n.s("A correction does not match the saved original values."))
                }
                values[old.id] = CompletedSet(id: old.id, exerciseID: old.exerciseID, setNumber: old.setNumber,
                    weight: change.weight, reps: change.reps, completedAt: old.completedAt, loggedUptime: old.loggedUptime)
                previousDate = change.recordedAt
            }
        }
    }
    public mutating func correctSet(sessionID: UUID, setID: UUID, expectedWeight: Double, expectedReps: Int,
                                    weight: Double, reps: Int, reason: String, now: Date = Date()) throws {
        guard let session = effectiveSession(sessionID), session.phase == .completed,
              let old = session.entries.first(where: { $0.id == setID }),
              old.weight == expectedWeight, old.reps == expectedReps else {
            throw WorkoutError.invalidState(L10n.s("This set changed while you were editing. Reopen it to review the current values."))
        }
        guard old.weight != weight || old.reps != reps else {
            throw WorkoutError.invalidInput(L10n.s("Change the load or repetitions before saving a correction."))
        }
        var next = self
        next.setCorrections = correctionLog + [SetCorrection(id: UUID(), sessionID: sessionID, setID: setID,
            previousWeight: old.weight, previousReps: old.reps, weight: weight, reps: reps, recordedAt: now,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))]
        try next.validateCorrections()
        // A review can include older workouts as context. Conservatively mark all
        // saved results stale and revoke every in-flight attempt; do not fabricate
        // a revised model answer or silently accept its old proposal.
        next.invalidateCoachEvidence(now: now)
        next.storageVersion = 3
        self = next
    }
    mutating func invalidateCoachEvidence(now: Date) {
        var jobs = reviewQueue
        for i in jobs.indices {
            if jobs[i].result != nil { jobs[i].outdatedAt = now }
            if jobs[i].status == .running {
                jobs[i].status = .failed; jobs[i].attemptID = nil
                jobs[i].detail = L10n.s("Workout evidence changed. Start a new review with the corrected report.")
            }
        }
        reviewJobs = jobs
        // Preserve imported/unlinked proposals too, because their context cannot
        // be proven independent of the corrected history.
        if let review {
            if !jobs.contains(where: { $0.result == review }), !(unlinkedCoachReviews ?? []).contains(where: { $0.response == review }) {
                var saved = unlinkedCoachReviews ?? []
                saved.append(UnlinkedCoachReview(id: UUID(), response: review, savedAt: now)); unlinkedCoachReviews = saved
            }
            self.review = nil
        }
        unlinkedCoachReviewsOutdatedAt = now
    }
}
