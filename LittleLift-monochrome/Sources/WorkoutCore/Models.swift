import Foundation

public enum WeightUnit: String, Codable, CaseIterable, Sendable { case kg, lb }

public struct ExercisePlan: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sets: Int
    public var reps: Int
    public var weight: Double
    public var restSeconds: Int
    public var comparisonID: String?
    public var loadConvention: LoadConvention?
    public var workPolicy: WorkPolicy?
    public var alternatives: [ExerciseAlternative]?

    public init(id: UUID = UUID(), name: String, sets: Int, reps: Int, weight: Double, restSeconds: Int = 90, comparisonID: String? = nil, loadConvention: LoadConvention? = nil) {
        self.id = id; self.name = name; self.sets = sets; self.reps = reps
        self.weight = weight; self.restSeconds = restSeconds
        self.comparisonID = comparisonID; self.loadConvention = loadConvention
    }
}

public struct WorkoutPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var unit: WeightUnit
    public var exercises: [ExercisePlan]
    public var observations: [ObservationRequest]?
    public var observationSchemaVersion: Int?
    public var timeBudget: TimeBudget?
    public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }

    public init(id: UUID = UUID(), title: String, unit: WeightUnit = .kg, exercises: [ExercisePlan], observations: [ObservationRequest]? = nil, observationSchemaVersion: Int? = nil) {
        self.id = id; self.title = title; self.unit = unit; self.exercises = exercises
        self.observations = observations; self.observationSchemaVersion = observationSchemaVersion
    }

    public func validate() throws {
        guard Self.validName(title) else {
            throw WorkoutError.invalidPlan("Give the workout a short title on a single line.")
        }
        guard (1...50).contains(exercises.count) else {
            throw WorkoutError.invalidPlan("A workout must contain 1–50 exercises and at most 200 sets.")
        }
        guard Set(exercises.map(\.id)).count == exercises.count else {
            throw WorkoutError.invalidPlan("Exercise identifiers must be unique.")
        }
        for exercise in exercises {
            try exercise.validateFlexibility()
            guard exercise.comparisonID.map(Self.validIdentifier) ?? true,
                  (exercise.comparisonID == nil) == (exercise.loadConvention == nil),
                  exercise.loadConvention != .bodyweight || exercise.weight == 0 else {
                throw WorkoutError.invalidPlan("Provide comparisonID and loadConvention together. Use a 1–64 character identifier for the exact variation. Bodyweight targets must have weight 0.")
            }
            guard Self.validName(exercise.name), (1...20).contains(exercise.sets),
                  (1...200).contains(exercise.reps), exercise.weight.isFinite,
                  (0...1000).contains(exercise.weight), (0...1800).contains(exercise.restSeconds) else {
                throw WorkoutError.invalidPlan("Use a short exercise name on one line, 1–20 sets, 1–200 reps, weight 0–1000, and rest 0–1800 seconds.")
            }
        }
        let allIDs = exercises.map(\.id) + exercises.flatMap { ($0.alternatives ?? []).map(\.id) }
        guard Set(allIDs).count == allIDs.count else { throw WorkoutError.invalidPlan("Exercise and alternative IDs must be distinct throughout the workout.") }
        if exercises.contains(where: { !($0.alternatives ?? []).isEmpty || $0.workPolicy != nil }) {
            let bytes = try FileRepository<WorkoutPlan>.encoder().encode(self).count
            guard bytes + totalSets * 255 + 1024 < 60_000 else {
                throw WorkoutError.invalidPlan("This flexible workout is too large to deliver safely when completed. Split it into smaller routines or remove alternatives.")
            }
        }
        try timeBudget?.validate()
        try validateObservations()
        guard totalSets <= 200 else {
            throw WorkoutError.invalidPlan("Keep a workout below 201 sets.")
        }
    }

    private static func validName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.utf8.count <= 120 &&
        !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

public enum WorkoutError: LocalizedError, Equatable, Sendable {
    case invalidPlan(String), invalidState(String), invalidInput(String)
    public var errorDescription: String? {
        switch self {
        case .invalidPlan(let text), .invalidState(let text), .invalidInput(let text): return text
        }
    }
}

public enum SessionPhase: String, Codable, Sendable { case active, resting, completed }

public struct CompletedSet: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let exerciseID: UUID
    public let setNumber: Int
    public let weight: Double
    public let reps: Int
    public let completedAt: Date
    public var loggedUptime: TimeInterval? = nil
}

public struct WorkoutSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let plan: WorkoutPlan
    public let startedAt: Date
    public private(set) var endedAt: Date?
    public private(set) var entries: [CompletedSet] = []
    public private(set) var phase: SessionPhase = .active
    public private(set) var restUntil: Date?
    public private(set) var restDuration: TimeInterval = 0
    public private(set) var effortResponse: EffortResponse?
    public private(set) var configuration: ExecutionConfiguration?
    public private(set) var previousConfiguration: ExecutionConfiguration?
    public private(set) var adjustmentEntryCount: Int?
    public private(set) var adjustments: [SessionAdjustment]?


    public init(id: UUID = UUID(), plan: WorkoutPlan, now: Date = Date()) throws {
        try plan.validate()
        self.id = id; self.plan = plan; self.startedAt = now
    }

    public var currentExercise: ExercisePlan? {
        executionExercises.first { exercise in !execution.omitted.contains(originalID(for: exercise.id)) && entries.filter { $0.exerciseID == exercise.id }.count < exercise.sets }
    }
    public var currentSetNumber: Int {
        guard let exercise = currentExercise else { return 0 }
        return entries.filter { $0.exerciseID == exercise.id }.count + 1
    }
    public var volume: Double { entries.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    public var duration: TimeInterval { max(0, (endedAt ?? Date()).timeIntervalSince(startedAt)) }

    public mutating func logSet(weight: Double, reps: Int, now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) throws {
        guard phase == .active, let exercise = currentExercise else {
            throw WorkoutError.invalidState("Finish or skip your rest before logging another set.")
        }
        guard weight.isFinite, (0...1000).contains(weight), (1...200).contains(reps), now >= (entries.last?.completedAt ?? startedAt),
              now.timeIntervalSince1970.isFinite, uptime.isFinite, uptime >= 0 else {
            throw WorkoutError.invalidInput("Use weight 0–1000 and 1–200 repetitions.")
        }
        if pendingEffort != nil { try answerEffort(nil, now: now) }
        let recordsTiming = true // New records support pace estimates; legacy timestamps remain untouched.
        entries.append(CompletedSet(id: UUID(), exerciseID: exercise.id, setNumber: currentSetNumber,
                                    weight: weight, reps: reps, completedAt: now, loggedUptime: recordsTiming ? uptime : nil))
        if currentExercise == nil { finish(now: now, resolveEffort: false) }
        else if exercise.restSeconds > 0 {
            phase = .resting
            restDuration = Double(exercise.restSeconds)
            restUntil = now.addingTimeInterval(restDuration)
        }
    }

    @discardableResult
    public mutating func endRestIfDue(now: Date = Date()) -> Bool {
        guard phase == .resting, let deadline = restUntil, now >= deadline else { return false }
        skipRest(); return true
    }

    public mutating func skipRest() {
        guard phase == .resting else { return }
        phase = .active; restUntil = nil; restDuration = 0
    }

    public mutating func extendRest(by seconds: TimeInterval = 30) throws {
        guard phase == .resting, let deadline = restUntil, seconds.isFinite, (1...300).contains(seconds),
              restDuration + seconds <= 3600 else { throw WorkoutError.invalidState("Rest cannot be extended further.") }
        restUntil = deadline.addingTimeInterval(seconds); restDuration += seconds
    }

    public mutating func undoLastSet() throws {
        guard phase != .completed, !entries.isEmpty else {
            throw WorkoutError.invalidState("There is no set to undo in this active workout.")
        }
        let removed = entries.removeLast()
        if configuration != nil {
            var config = execution; let original = originalID(for: removed.exerciseID)
            config.order.removeAll { $0 == original }; config.order.insert(original, at: 0); configuration = config
        }
        if effortResponse?.setID == removed.id { effortResponse = nil }
        phase = .active; restUntil = nil; restDuration = 0
    }

    public mutating func answerEffort(_ rating: Int?, now: Date = Date()) throws {
        guard let request = pendingEffort, let entry = entries.first(where: { $0.exerciseID == request.exerciseID && $0.setNumber == request.afterSet }),
              rating.map({ (1...10).contains($0) }) ?? true, now >= entry.completedAt, now.timeIntervalSince1970.isFinite else {
            throw WorkoutError.invalidInput("Choose an effort from 1–10, or skip the pending question.")
        }
        effortResponse = EffortResponse(requestID: request.id, setID: entry.id, rating: rating, recordedAt: now)
    }

    private mutating func changeExecution(_ next: ExecutionConfiguration, detail: String, now: Date) throws {
        guard phase != .completed, (adjustments?.count ?? 0) < 99 else { throw WorkoutError.invalidState("No more changes can be made in this session.") }
        let old = execution
        var candidate = self; candidate.configuration = next
        try candidate.validateExecution()
        candidate.previousConfiguration = old; candidate.adjustmentEntryCount = entries.count
        var log = adjustments ?? []; log.append(SessionAdjustment(id: UUID(), date: now, detail: detail)); candidate.adjustments = log
        try candidate.validateDeliveryReserve()
        self = candidate
    }
    public mutating func deferCurrent(now: Date = Date()) throws {
        guard let current = currentExercise, remainingExercises.count > 1 else { throw WorkoutError.invalidState("No other exercise remains. Return when the machine is available.") }
        let id = originalID(for: current.id); var next = execution
        next.order.removeAll { $0 == id }; next.order.append(id)
        try changeExecution(next, detail: "Deferred \(current.name); completed sets and rest unchanged.", now: now)
    }
    public mutating func substituteCurrent(with alternativeID: UUID, now: Date = Date()) throws {
        guard phase != .completed, let current = currentExercise, let original = plan.exercises.first(where: { $0.id == originalID(for: current.id) }),
              !entries.contains(where: { originalID(for: $0.exerciseID) == original.id }),
              let alternative = original.alternatives?.first(where: { $0.id == alternativeID }), alternative.unit == plan.unit else {
            throw WorkoutError.invalidInput("Choose a previously approved alternative with the same units before logging any sets of this exercise.")
        }
        var next = execution; next.substitutions.removeAll { $0.originalID == original.id }
        next.substitutions.append(Substitution(originalID: original.id, alternativeID: alternative.id))
        try changeExecution(next, detail: "Approved substitution: \(original.name) → \(alternative.name); \(alternative.reps) reps at \(Self.number(alternative.weight)) \(alternative.unit.rawValue), \(alternative.restSeconds)s prescribed rest. Original observation requests are not transferred to this variation.", now: now)
    }
    public mutating func omitOptional(_ ids: [UUID], now: Date = Date()) throws {
        let approved = Set(WorkoutPace.optionalCandidates(self).map { originalID(for: $0.id) })
        guard !ids.isEmpty, Set(ids).isSubset(of: approved), currentExercise.map({ !ids.contains(originalID(for: $0.id)) }) ?? false else {
            throw WorkoutError.invalidInput("Only untouched, approved optional work after the current exercise can be removed.")
        }
        var next = execution; next.omitted = Array(Set(next.omitted + ids))
        let names = plan.exercises.filter { ids.contains($0.id) }.map(\.name).joined(separator: ", ")
        try changeExecution(next, detail: "Omitted approved optional work: \(names). Loads, repetitions, completed sets and required rest unchanged.", now: now)
    }
    public mutating func undoAdjustment(now: Date = Date()) throws {
        guard let previousConfiguration, adjustmentEntryCount == entries.count, phase != .completed else {
            throw WorkoutError.invalidState("This change can be reversed before another set is logged. Completed sets are never removed by reversing a plan change.")
        }
        var candidate = self; candidate.configuration = previousConfiguration; try candidate.validateExecution()
        candidate.previousConfiguration = nil; candidate.adjustmentEntryCount = nil
        var log = adjustments ?? []; log.append(SessionAdjustment(id: UUID(), date: now, detail: "Reversed the last workout change before logging another set.")); candidate.adjustments = log
        try candidate.validateDeliveryReserve(); self = candidate
    }

    public mutating func finish(now: Date = Date(), resolveEffort: Bool = true) {
        guard phase != .completed else { return }
        if resolveEffort, let request = pendingEffort, let entry = entries.last(where: { $0.exerciseID == request.exerciseID }) {
            effortResponse = EffortResponse(requestID: request.id, setID: entry.id, rating: nil, recordedAt: max(now, entry.completedAt))
        }
        phase = .completed; endedAt = max(now, entries.last?.completedAt ?? startedAt, startedAt)
        restUntil = nil; restDuration = 0
    }

    public func validateCompleted() throws {
        try plan.validate()
        try validateEffort()
        try validateExecution()
        guard isReadyForDelivery, let end = endedAt, end >= startedAt,
              InputBoundary.validDate(startedAt), InputBoundary.validDate(end),
              entries.count <= plan.totalSets, Set(entries.map(\.id)).count == entries.count else {
            throw WorkoutError.invalidInput("The received workout is incomplete or invalid.")
        }
        var seen = Set<String>()
        var previousDate = startedAt
        var counts: [UUID: Int] = [:]
        for entry in entries {
            guard let exercise = executionExercises.first(where: { $0.id == entry.exerciseID }),
                  (1...exercise.sets).contains(entry.setNumber), (1...200).contains(entry.reps),
                  entry.weight.isFinite, (0...1000).contains(entry.weight),
                  entry.completedAt >= previousDate, entry.completedAt <= end,
                  entry.setNumber == (counts[entry.exerciseID] ?? 0) + 1,
                  entry.loggedUptime.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  seen.insert("\(entry.exerciseID)-\(entry.setNumber)").inserted else {
                throw WorkoutError.invalidInput("A received set has invalid or duplicate values.")
            }
            previousDate = entry.completedAt
            counts[entry.exerciseID] = entry.setNumber
        }
    }

    public func report() -> String {
        let date = ISO8601DateFormatter().string(from: startedAt)
        var lines = ["WORKOUT LOG", "Session ID: \(id.uuidString)", "Date: \(date)",
                     "Workout: \(plan.title)", "Duration: \(Int(duration / 60)) min",
                     "Completed: \(entries.count) / \(plan.totalSets) sets", "Units: \(plan.unit.rawValue)", ""]
        for exercise in executionExercises {
            lines.append(exercise.name)
            lines.append("  Load convention: \(exercise.loadConvention?.label ?? "unspecified; cross-workout comparison unavailable")")
            lines.append("  Variation ID: \(exercise.comparisonID ?? "unspecified")")
            let logged = entries.filter { $0.exerciseID == exercise.id }
            if logged.isEmpty { lines.append("  Not completed") }
            for entry in logged {
                lines.append("  Set \(entry.setNumber) (user-confirmed): \(Self.number(entry.weight)) \(plan.unit.rawValue) × \(entry.reps) reps")
            }
        }
        if let adjustments, !adjustments.isEmpty {
            lines.append("\nEXPLICIT WORKOUT CHANGES (original prescription preserved)")
            for change in adjustments { lines.append(change.detail) }
            for original in plan.exercises { lines.append("Original: \(original.name), \(original.sets) × \(original.reps), \(Self.number(original.weight)) \(plan.unit.rawValue), rest \(original.restSeconds)s") }
        }
        if !observationEvidence.isEmpty {
            lines.append("\nCOACH OBSERVATIONS")
            for evidence in observationEvidence {
                lines.append("[\(evidence.requestID)] \(evidence.title) · Set ID: \(evidence.setID?.uuidString ?? "not logged")\n\(evidence.detail)")
            }
        }
        lines.append("\nPlease log these actual results and give descriptive feedback. Do not treat uncompleted sets as completed. Compare across workouts only when variation IDs, units and load conventions match; otherwise explain insufficient data. Log-tap intervals include exercise time and do not measure actual rest. No set-start/end or motion measurements were collected. Do not infer causation, injury risk or medical readiness. Propose any next plan for my review; never assume it has been accepted.")
        return lines.joined(separator: "\n")
    }

    public static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

public struct TrainingReview: Codable, Equatable, Sendable {
    public let analysis: String
    public let plan: WorkoutPlan
    public init(analysis: String, plan: WorkoutPlan) { self.analysis = analysis; self.plan = plan }
}

public enum ConnectionMode: String, Codable, CaseIterable, Sendable {
    case existingChat, shortcut
    public var title: String { self == .existingChat ? "My existing chat" : "Review Shortcut" }
}

public struct PhoneState: Codable, Equatable, Sendable {
    public var plan: WorkoutPlan?
    public var sessions: [WorkoutSession] = []
    public var profile = ""
    public var mode: ConnectionMode = .existingChat
    public var review: TrainingReview?
    public var routines: [Routine]?
    public var schedule: [WeeklySlot]?
    public var importedHistory: [HistoricalWorkout]?
    public var reviewJobs: [ReviewJob]?
    public var reviewNotificationsEnabled: Bool?
    public var selectedReviewSessionID: UUID?
    public var doubleTapEnabled: Bool?
    public var motionOptIn: Bool?
    public var motionExercise: MotionExercise?
    public init() {}

    public mutating func propose(_ review: TrainingReview) throws {
        try review.plan.validate(); self.review = review
    }
    public mutating func acceptReview() throws {
        guard let review else { return }
        try review.plan.validate(); plan = review.plan; self.review = nil
    }

    public mutating func receive(_ session: WorkoutSession) throws {
        try session.validateCompleted()
        if let original = sessions.first(where: { $0.id == session.id }) {
            guard original == session else {
                throw WorkoutError.invalidInput("A different workout already has this ID. The saved original was preserved; the conflicting delivery was not acknowledged.")
            }
            return
        }
        sessions.append(session); sessions.sort { $0.startedAt > $1.startedAt }
        queueReview(for: session.id)
    }
}

public struct WatchState: Codable, Equatable, Sendable {
    public var plan: WorkoutPlan?
    public var session: WorkoutSession?
    public var outbox: [WorkoutSession] = []
    public var recent: [WorkoutSession] = []
    public var haptics = true
    public var doubleTapEnabled: Bool?
    public var motionOptIn: Bool?
    public var motionExercise: MotionExercise?
    public var lastSnapshotDate: Date?
    public init() {}

    public mutating func enqueueCompleted() {
        guard let session, session.isReadyForDelivery,
              !outbox.contains(where: { $0.id == session.id }) else { return }
        outbox.append(session)
        if !recent.contains(where: { $0.id == session.id }) { recent.insert(session, at: 0) }
        recent = Array(recent.prefix(30))
    }

    public mutating func acknowledge(_ ids: [UUID]) { outbox.removeAll { ids.contains($0.id) } }
}

public struct PhoneSnapshot: Codable, Equatable, Sendable {
    public let plan: WorkoutPlan?
    public let acknowledged: [UUID]
    public let issuedAt: Date
    public let doubleTapEnabled: Bool?
    public let motionOptIn: Bool?
    public let motionExercise: MotionExercise?
    public init(plan: WorkoutPlan?, acknowledged: [UUID], issuedAt: Date = Date(), doubleTapEnabled: Bool? = nil, motionOptIn: Bool? = nil, motionExercise: MotionExercise? = nil) {
        self.motionExercise = motionExercise
        self.motionOptIn = motionOptIn
        self.doubleTapEnabled = doubleTapEnabled
        self.plan = plan; self.acknowledged = acknowledged; self.issuedAt = issuedAt
    }
    private enum CodingKeys: String, CodingKey { case plan, acknowledged, issuedAt, doubleTapEnabled, motionOptIn, motionExercise }
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        motionOptIn = try fields.decodeIfPresent(Bool.self, forKey: .motionOptIn)
        motionExercise = try fields.decodeIfPresent(MotionExercise.self, forKey: .motionExercise)
        doubleTapEnabled = try fields.decodeIfPresent(Bool.self, forKey: .doubleTapEnabled)
        plan = try fields.decodeIfPresent(WorkoutPlan.self, forKey: .plan)
        acknowledged = try fields.decode([UUID].self, forKey: .acknowledged)
        issuedAt = try fields.decodeIfPresent(Date.self, forKey: .issuedAt) ?? .distantPast
    }
}

public enum SyncMessage: Codable, Equatable, Sendable {
    case snapshot(PhoneSnapshot)
    case completed(WorkoutSession)
    case requestSnapshot
    case planReceived(UUID)
}
