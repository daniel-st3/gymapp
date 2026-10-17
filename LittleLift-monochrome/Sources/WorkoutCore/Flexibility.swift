import Foundation

/// Alternatives are approved prescriptions, not generated substitutions.
public struct ExerciseAlternative: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var comparisonID: String
    public var loadConvention: LoadConvention
    public var unit: WeightUnit
    public var reps: Int
    public var weight: Double
    public var restSeconds: Int
    public init(id: UUID = UUID(), name: String, comparisonID: String, loadConvention: LoadConvention, unit: WeightUnit, reps: Int, weight: Double, restSeconds: Int) {
        self.id = id; self.name = name; self.comparisonID = comparisonID; self.loadConvention = loadConvention
        self.unit = unit; self.reps = reps; self.weight = weight; self.restSeconds = restSeconds
    }
    public func exercise(sets: Int) -> ExercisePlan {
        ExercisePlan(id: id, name: name, sets: sets, reps: reps, weight: weight, restSeconds: restSeconds, comparisonID: comparisonID, loadConvention: loadConvention)
    }
}
extension ExercisePlan {
    public func validateFlexibility() throws {
        guard workPolicy.map({ (1...5).contains($0.priority) }) ?? true, (alternatives?.count ?? 0) <= 5 else {
            throw WorkoutError.invalidPlan(L10n.s("Priority must be 1–5, with at most five previously approved alternatives per exercise."))
        }
        let choices = alternatives ?? []
        guard Set(choices.map(\.id)).count == choices.count, !choices.contains(where: { $0.id == id }) else { throw WorkoutError.invalidPlan(L10n.s("Alternatives need unique IDs distinct from the original.")) }
        for choice in choices {
            guard WorkoutPlan.validIdentifier(choice.comparisonID) else { throw WorkoutError.invalidPlan(L10n.s("An alternative needs its own exact variation identifier.")) }
            try WorkoutPlan(title: L10n.s("Alternative"), unit: choice.unit, exercises: [choice.exercise(sets: sets)]).validate()
        }
    }
}

public struct ExecutionConfiguration: Codable, Equatable, Sendable {
    public var order: [UUID]
    public var omitted: [UUID]
    public var substitutions: [Substitution]
    public var skipped: [UUID]?
    public init(order: [UUID], omitted: [UUID] = [], substitutions: [Substitution] = []) { self.order = order; self.omitted = omitted; self.substitutions = substitutions }
}
public struct Substitution: Codable, Equatable, Sendable {
    public let originalID: UUID
    public let alternativeID: UUID
    public var proposeForFuture: Bool?
    public var reason: String?
}
public struct SessionAdjustment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let detail: String
}
public struct TimeBudget: Codable, Equatable, Sendable {
    public var durationMinutes: Int?
    public var finishAt: Date?
    public init(durationMinutes: Int? = nil, finishAt: Date? = nil) { self.durationMinutes = durationMinutes; self.finishAt = finishAt }
    public func deadline(start: Date) -> Date? { finishAt ?? durationMinutes.map { start.addingTimeInterval(Double($0 * 60)) } }
    public func validate() throws {
        guard (durationMinutes == nil) != (finishAt == nil), durationMinutes.map({ (5...360).contains($0) }) ?? true,
              finishAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { throw WorkoutError.invalidInput(L10n.s("Choose either a duration of 5–360 minutes or a finish time.")) }
    }
}
public struct PaceEstimate: Equatable, Sendable {
    public let lower: TimeInterval
    public let upper: TimeInterval
    public let sampleCount: Int
    public var text: String {
        let evidence = sampleCount == 0 ? L10n.s("limited history; broad estimate") : L10n.s("\(sampleCount) matched logging intervals")
        return L10n.s("\(Int(ceil(lower / 60)))–\(Int(ceil(upper / 60))) min remaining · \(evidence)")
    }
}
public enum WorkoutPace {
    public static func remaining(_ session: WorkoutSession, history: [WorkoutSession], now: Date = Date()) -> PaceEstimate {
        guard session.phase != .completed else { return PaceEstimate(lower: 0, upper: 0, sampleCount: 0) }
        let live = [session] + history.filter {
            $0.id != session.id && $0.plan.practice != true && $0.phase == .completed &&
            $0.endedAt.map { $0 <= session.startedAt } == true
        }.sorted { $0.startedAt < $1.startedAt }
        let transition = max(0, session.transitionUntil?.timeIntervalSince(now) ?? session.transitionRemaining ?? 0)
        let remainingExercises = session.remainingExercises
        let changes = max(0, remainingExercises.count - 1) + (session.pendingTransition == true ? 1 : 0)
        let futureChanges = changes * (session.plan.transitionSeconds ?? 0)
        var low = max(0, session.restUntil?.timeIntervalSince(now) ?? 0) + transition + Double(futureChanges), high = low, samples = 0
        for (index, exercise) in remainingExercises.enumerated() {
            let remaining = max(0, exercise.sets - session.completedCount(for: exercise))
            guard remaining > 0 else { continue }
            if let activity = exercise.activity {
                let elapsed = session.activityTimer?.exerciseID == exercise.id ? session.activityTimer?.elapsed(at: now) ?? 0 : 0
                low += max(0, (activity.durationSeconds ?? 60) - elapsed)
                high += max(0, (activity.durationSeconds ?? 1200) - elapsed)
                continue
            }
            var intervals: [Double] = []
            for previous in live {
                let matched = previous.executionExercises.filter { $0.matches(exercise, unit: previous.plan.unit, otherUnit: session.plan.unit) }
                // Repeated variations in one workout have ambiguous fatigue/order.
                if matched.count == 1, let match = matched.first {
                    for e in previous.entries where e.exerciseID == match.id {
                        if let interval = previous.loggingInterval(before: e), interval >= 5, interval <= 1800 {
                            // This is a planning assumption, not measured work or
                            // rest: observed tap interval minus prescribed rest.
                            intervals.append(max(15, interval - Double(match.restSeconds)))
                        }
                    }
                }
            }
            intervals = Array(intervals.suffix(30)).sorted(); samples += intervals.count
            let minimum = intervals.first ?? 25
            let maximum = max(minimum + 30, intervals.last ?? 120)
            // No rest follows the final set of the entire workout. The current
            // rest (including extensions) was counted above; never count it twice.
            let restCount = remaining - (index == remainingExercises.count - 1 ? 1 : 0)
            let rests = Double(max(0, restCount) * exercise.restSeconds)
            low += minimum * Double(remaining) + rests
            high += maximum * Double(remaining) + rests
        }
        // Transition allowance is separate from the full set logging interval.
        return PaceEstimate(lower: low, upper: high, sampleCount: samples)
    }
    public static func shorterProposal(_ session: WorkoutSession, history: [WorkoutSession], now: Date = Date()) -> [ExercisePlan] {
        let current = session.currentExercise.map { session.originalID(for: $0.id) }
        let candidates = optionalCandidates(session).filter { session.originalID(for: $0.id) != current }
        guard let deadline = session.plan.timeBudget?.deadline(start: session.startedAt) else { return candidates }
        let available = max(0, deadline.timeIntervalSince(now))
        guard remaining(session, history: history, now: now).upper > available else { return [] }
        var chosen: [ExercisePlan] = []; var shortened = session
        for candidate in candidates {
            chosen.append(candidate)
            try? shortened.omitOptional([session.originalID(for: candidate.id)], now: now)
            if remaining(shortened, history: history, now: now).upper <= available { break }
        }
        return chosen
    }
    public static func optionalCandidates(_ session: WorkoutSession) -> [ExercisePlan] {
        session.remainingExercises.filter { exercise in
            exercise.workPolicy?.optional == true && !session.execution.omitted.contains(session.originalID(for: exercise.id)) &&
            !session.entries.contains(where: { $0.exerciseID == exercise.id }) &&
            !(session.activities ?? []).contains(where: { $0.exerciseID == exercise.id }) && session.activityTimer?.exerciseID != exercise.id
        }.sorted { ($0.workPolicy?.priority ?? 3) > ($1.workPolicy?.priority ?? 3) }
    }
}

extension WorkoutSession {
    public var execution: ExecutionConfiguration { configuration ?? ExecutionConfiguration(order: plan.exercises.map(\.id)) }
    public var executionExercises: [ExercisePlan] {
        execution.order.compactMap { id in
            guard let original = plan.exercises.first(where: { $0.id == id }) else { return nil }
            if let substitution = execution.substitutions.first(where: { $0.originalID == id }),
               let choice = original.alternatives?.first(where: { $0.id == substitution.alternativeID }) {
                var e = choice.exercise(sets: original.sets); e.workPolicy = original.workPolicy; return e
            }
            return original
        }
    }
    public func originalID(for executionID: UUID) -> UUID { execution.substitutions.first { $0.alternativeID == executionID }?.originalID ?? executionID }
    public var remainingExercises: [ExercisePlan] {
        executionExercises.filter { exercise in !execution.omitted.contains(originalID(for: exercise.id)) && !(execution.skipped ?? []).contains(originalID(for: exercise.id)) && completedCount(for: exercise) < exercise.sets }
    }
    /// Reserve space for every still-prescribed set, an effort answer and completion.
    /// This is a byte budget only; no synthetic measurements enter stored history.
    func validateDeliveryReserve() throws {
        let bytes = try FileRepository<WorkoutSession>.encoder().encode(self).count
        let future = executionExercises.reduce(0) { $0 + max(0, $1.sets - completedCount(for: $1)) * ($1.kind == .strength ? 255 : 1000) }
        guard bytes + future + 1024 < 60_000 else {
            throw WorkoutError.invalidState(L10n.s("This change would leave too little room to deliver the completed workout. Continue logging the current prescription."))
        }
    }
    public func validateExecution() throws {
        let config = execution, ids = Set(plan.exercises.map(\.id))
        guard config.order.count == ids.count, Set(config.order) == ids, Set(config.omitted).count == config.omitted.count,
              Set(config.omitted).isSubset(of: ids), (adjustments?.count ?? 0) <= 100,
              Set(config.substitutions.map(\.originalID)).count == config.substitutions.count else { throw WorkoutError.invalidInput(L10n.s("Invalid workout execution order or changes.")) }
        guard Set(config.skipped ?? []).isSubset(of: ids), Set(config.skipped ?? []).count == (config.skipped?.count ?? 0), Set(config.skipped ?? []).isDisjoint(with: config.omitted) else { throw WorkoutError.invalidInput(L10n.s("Invalid skipped exercises.")) }
        for id in config.omitted {
            guard plan.exercises.first(where: { $0.id == id })?.workPolicy?.optional == true,
                  !entries.contains(where: { originalID(for: $0.exerciseID) == id }), !(activities ?? []).contains(where: { $0.exerciseID == id }) else { throw WorkoutError.invalidInput(L10n.s("Only untouched, approved optional exercises may be omitted.")) }
        }
        for s in config.substitutions {
            guard (s.reason?.count ?? 0) <= 120 else { throw WorkoutError.invalidInput(L10n.s("Keep the substitution reason short.")) }
            guard let original = plan.exercises.first(where: { $0.id == s.originalID }), let alt = original.alternatives?.first(where: { $0.id == s.alternativeID }), alt.unit == plan.unit else { throw WorkoutError.invalidInput(L10n.s("Substitution was not approved with matching units.")) }
        }
    }
}

extension WorkoutSession {
    public var nextSessionProposal: WorkoutPlan? {
        let requests = execution.substitutions.filter { $0.proposeForFuture == true }
        guard !requests.isEmpty else { return nil }
        var next = plan; next.id = UUID()
        next.exercises = plan.exercises.map { original in
            guard let request = requests.first(where: { $0.originalID == original.id }), let alternative = original.alternatives?.first(where: { $0.id == request.alternativeID }) else { return original }
            return alternative.exercise(sets: original.sets)
        }
        next.observations = plan.observations?.filter { request in next.exercises.contains { $0.id == request.exerciseID } }
        return next
    }
}
