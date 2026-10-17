import Foundation

/// A read-only review of durable records. No model, network, inferred measurements,
/// new prescription or second persistence queue is required for this review.
public struct WorkoutEvidenceReview: Sendable {
    public struct SetComparison: Identifiable, Sendable {
        public let entry: CompletedSet
        public let exercise: ExercisePlan
        public let previous: CompletedSet?
        public let previousSessionID: UUID?
        public let previousDate: Date?
        public var id: UUID { entry.id }
    }
    public let session: WorkoutSession
    public let comparisons: [SetComparison]
    public var strengthSets: Int { session.entries.count }
    public var timedSegments: Int { session.activities?.count ?? 0 }
    public var matchedSets: Int { comparisons.filter { $0.previous != nil }.count }

    public init(session: WorkoutSession, history: [WorkoutSession]) {
        self.session = session
        // A later delivery can add an older comparison, but a workout performed
        // later (or still in progress) can never become this workout's baseline.
        let previous = history.filter {
            $0.id != session.id && $0.phase == .completed && $0.plan.practice != true &&
            $0.endedAt.map { $0 <= session.startedAt } == true && $0.startedAt < session.startedAt
        }.sorted { a, b in
            if a.startedAt != b.startedAt { return a.startedAt > b.startedAt }
            return a.id.uuidString < b.id.uuidString
        }
        comparisons = session.entries.compactMap { entry in
            guard let exercise = session.executionExercises.first(where: { $0.id == entry.exerciseID }) else { return nil }
            let currentVariants = session.executionExercises.filter { exercise.matches($0, unit: session.plan.unit, otherUnit: session.plan.unit) }
            if session.plan.practice != true && currentVariants.count == 1 {
                for prior in previous {
                    // Ambiguous repeated variation identities are not guessed.
                    let variants = prior.executionExercises.filter {
                        $0.kind == .strength && exercise.matches($0, unit: session.plan.unit, otherUnit: prior.plan.unit)
                    }
                    guard variants.count == 1, let variant = variants.first else { continue }
                    if let match = prior.entries.first(where: { $0.exerciseID == variant.id && $0.setNumber == entry.setNumber }) {
                        return SetComparison(entry: entry, exercise: exercise, previous: match, previousSessionID: prior.id, previousDate: prior.startedAt)
                    }
                }
            }
            return SetComparison(entry: entry, exercise: exercise, previous: nil, previousSessionID: nil, previousDate: nil)
        }
    }

    public var summary: String {
        L10n.s("Strength sets recorded: \(strengthSets). Timed segments recorded: \(timedSegments). Sets with a comparable earlier record: \(matchedSets).")
    }
    public var timingNote: String {
        L10n.s("Strength timing is the interval between Log taps, including exercise time. Actual rest and repetition timing are unavailable. Timed activities use your Start, Pause, Resume and Done events.")
    }
    public func comparisonText(_ item: SetComparison) -> String {
        guard let prior = item.previous else {
            return session.plan.practice == true ? L10n.s("Practice workout: excluded from historical comparisons.") : L10n.s("No comparable earlier set. Exact variation, unit, load convention and set number must match.")
        }
        let load = item.entry.weight - prior.weight, reps = item.entry.reps - prior.reps
        let loadChange = (load > 0 ? "+" : "") + WorkoutSession.number(load)
        let repChange = (reps > 0 ? "+" : "") + String(reps)
        return L10n.s("Previous: \(WorkoutSession.number(prior.weight)) \(session.plan.unit.rawValue) × \(prior.reps). Change: \(loadChange) \(session.plan.unit.rawValue), \(repChange) rep.")
    }
    public func report() -> String {
        var lines = [L10n.s("Automatic workout review · calculated on this iPhone"), summary, timingNote]
        for item in comparisons {
            lines.append(L10n.s("\(item.exercise.name) · Set \(item.entry.setNumber): \(comparisonText(item))"))
        }
        lines.append(session.report())
        return lines.joined(separator: "\n\n")
    }
}

extension PhoneState {
    /// Only acknowledged, validated completed records can have a local review.
    /// Deriving it from the saved session preserves idempotence and old schemas.
    public func localReview(for id: UUID) -> WorkoutEvidenceReview? {
        guard let session = sessions.first(where: { $0.id == id && $0.phase == .completed }) else { return nil }
        return WorkoutEvidenceReview(session: session, history: sessions)
    }
}

public enum RhythmEligibility {
    public static func allows(appActive: Bool, workoutRunning: Bool, haptics: Bool, enabled: Bool, sameSet: Bool) -> Bool {
        haptics && enabled && sameSet && (appActive || workoutRunning)
    }
}
