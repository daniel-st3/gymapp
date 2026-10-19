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
    public var activity: ActivityPrescription?
    /// Schema 3: numeric storage stays compatible; zero is not a prescribed load.
    public var loadIsUnspecified: Bool?

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
    public var schemaVersion: Int?
    public var transitionSeconds: Int?
    public var practice: Bool?
    public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }

    public init(id: UUID = UUID(), title: String, unit: WeightUnit = .kg, exercises: [ExercisePlan], observations: [ObservationRequest]? = nil, observationSchemaVersion: Int? = nil) {
        self.id = id; self.title = title; self.unit = unit; self.exercises = exercises
        self.observations = observations; self.observationSchemaVersion = observationSchemaVersion
    }

    public func validate() throws {
        guard Self.validName(title) else {
            throw WorkoutError.invalidPlan(L10n.s("Give the workout a short title on a single line."))
        }
        guard (1...50).contains(exercises.count) else {
            throw WorkoutError.invalidPlan(L10n.s("A workout must contain 1–50 exercises and at most 200 sets."))
        }
        guard Set(exercises.map(\.id)).count == exercises.count else {
            throw WorkoutError.invalidPlan(L10n.s("Exercise identifiers must be unique."))
        }
        guard schemaVersion == nil || schemaVersion == 1 || schemaVersion == 2 || schemaVersion == 3,
              transitionSeconds.map({ (0...300).contains($0) }) ?? true else { throw WorkoutError.invalidPlan(L10n.s("Unsupported workout schema or transition time.")) }
        for exercise in exercises {
            guard exercise.loadIsUnspecified != true || (schemaVersion == 3 && exercise.activity == nil && exercise.weight == 0 && exercise.loadConvention != .bodyweight) else {
                throw WorkoutError.invalidPlan(L10n.s("An unspecified load needs schema 3 and no numeric load target."))
            }
            try exercise.activity?.validate()
            if exercise.activity != nil {
                guard exercise.sets == 1, exercise.reps == 1, exercise.weight == 0, exercise.comparisonID == nil, exercise.loadConvention == nil, exercise.alternatives?.isEmpty ?? true else {
                    throw WorkoutError.invalidPlan(L10n.s("Timed activities use one segment, without strength repetitions, load conventions or automatic substitutions."))
                }
            }
            try exercise.validateFlexibility()
            guard exercise.comparisonID.map(Self.validIdentifier) ?? true,
                  ((exercise.comparisonID == nil) == (exercise.loadConvention == nil) || (schemaVersion == 3 && exercise.comparisonID == nil)),
                  exercise.loadConvention != .bodyweight || exercise.weight == 0 else {
                throw WorkoutError.invalidPlan(L10n.s("Provide comparisonID and loadConvention together. Use a 1–64 character identifier for the exact variation. Bodyweight targets must have weight 0."))
            }
            guard Self.validName(exercise.name), (1...20).contains(exercise.sets),
                  (1...200).contains(exercise.reps), exercise.weight.isFinite,
                  (0...1000).contains(exercise.weight), (0...1800).contains(exercise.restSeconds) else {
                throw WorkoutError.invalidPlan(L10n.s("Use a short exercise name on one line, 1–20 sets, 1–200 reps, weight 0–1000, and rest 0–1800 seconds."))
            }
        }
        let allIDs = exercises.map(\.id) + exercises.flatMap { ($0.alternatives ?? []).map(\.id) }
        guard Set(allIDs).count == allIDs.count else { throw WorkoutError.invalidPlan(L10n.s("Exercise and alternative IDs must be distinct throughout the workout.")) }
        if exercises.contains(where: { !($0.alternatives ?? []).isEmpty || $0.workPolicy != nil || $0.activity != nil }) {
            let bytes = try FileRepository<WorkoutPlan>.encoder().encode(self).count
            guard bytes + exercises.reduce(0, { $0 + $1.sets * ($1.kind == .strength ? 255 : 1000) }) + 1024 < 60_000 else {
                throw WorkoutError.invalidPlan(L10n.s("This flexible workout is too large to deliver safely when completed. Split it into smaller routines or remove alternatives."))
            }
        }
        try timeBudget?.validate()
        try validateObservations()
        guard totalSets <= 200 else {
            throw WorkoutError.invalidPlan(L10n.s("Keep a workout below 201 sets."))
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

public enum SessionPhase: String, Codable, Sendable { case active, resting, transitioning, completed }

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
    public private(set) var activities: [ActivityResult]?
    public private(set) var activityTimer: ActivityTimer?
    public private(set) var transitionUntil: Date?
    public private(set) var transitionRemaining: Double?
    public private(set) var pendingTransition: Bool?
    public private(set) var appliedCorrections: [SetCorrection]?
    public var feedback: String?
    public var hydrationDue: Date?


    public init(id: UUID = UUID(), plan: WorkoutPlan, now: Date = Date()) throws {
        try plan.validate()
        self.id = id; self.plan = plan; self.startedAt = now
    }

    public func applying(_ corrections: [SetCorrection]) -> WorkoutSession {
        var copy = self
        for change in corrections where change.sessionID == id {
            guard let index = copy.entries.firstIndex(where: { $0.id == change.setID }) else { continue }
            let old = copy.entries[index]
            copy.entries[index] = CompletedSet(id: old.id, exerciseID: old.exerciseID, setNumber: old.setNumber,
                weight: change.weight, reps: change.reps, completedAt: old.completedAt, loggedUptime: old.loggedUptime)
        }
        copy.appliedCorrections = corrections.isEmpty ? nil : corrections
        return copy
    }
    public var correctionSummary: String? {
        guard let changes = appliedCorrections, !changes.isEmpty else { return nil }
        var lines = [L10n.s("CORRECTED ON IPHONE — original Log events and prescription preserved.")]
        for change in changes {
            let number = entries.first(where: { $0.id == change.setID })?.setNumber ?? 0
            lines.append(L10n.s("Set \(number) [\(change.setID.uuidString)]: \(Self.number(change.previousWeight)) × \(change.previousReps) → \(Self.number(change.weight)) × \(change.reps) \(plan.unit.rawValue). \(change.reason)"))
            lines.append(ISO8601DateFormatter().string(from: change.recordedAt))
        }
        return lines.joined(separator: "\n")
    }

    public var currentExercise: ExercisePlan? {
        executionExercises.first { exercise in !execution.omitted.contains(originalID(for: exercise.id)) && !(execution.skipped ?? []).contains(originalID(for: exercise.id)) && completedCount(for: exercise) < exercise.sets }
    }
    public var currentSetNumber: Int {
        guard let exercise = currentExercise else { return 0 }
        return entries.filter { $0.exerciseID == exercise.id }.count + 1
    }
    public var volume: Double { entries.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    public var duration: TimeInterval { max(0, (endedAt ?? Date()).timeIntervalSince(startedAt)) }

    public mutating func logSet(weight: Double, reps: Int, now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) throws {
        guard phase == .active, let exercise = currentExercise, exercise.kind == .strength else {
            throw WorkoutError.invalidState(L10n.s("Finish or skip your rest before logging another set."))
        }
        guard weight.isFinite, (0...1000).contains(weight), (1...200).contains(reps), now >= latestWorkDate,
              now.timeIntervalSince1970.isFinite, uptime.isFinite, uptime >= 0 else {
            throw WorkoutError.invalidInput(L10n.s("Use weight 0–1000 and 1–200 repetitions."))
        }
        if pendingEffort != nil { try answerEffort(nil, now: now) }
        // New records support pace estimates; legacy timestamps remain untouched.
        entries.append(CompletedSet(id: UUID(), exerciseID: exercise.id, setNumber: currentSetNumber,
                                    weight: weight, reps: reps, completedAt: now, loggedUptime: uptime))
        pendingTransition = currentExercise?.id != exercise.id && currentExercise != nil
        if currentExercise == nil { finish(now: now, resolveEffort: false) }
        else if exercise.restSeconds > 0 {
            phase = .resting
            restDuration = Double(exercise.restSeconds)
            restUntil = now.addingTimeInterval(restDuration)
        } else { beginTransition(now: now) }
    }

    @discardableResult
    public mutating func endRestIfDue(now: Date = Date()) -> Bool {
        guard phase == .resting, let deadline = restUntil, now >= deadline else { return false }
        skipRest(now: now); return true
    }

    public mutating func skipRest(now: Date = Date()) {
        guard phase == .resting else { return }
        phase = .active; restUntil = nil; restDuration = 0; beginTransition(now: now)
    }

    public mutating func extendRest(by seconds: TimeInterval = 30) throws {
        guard phase == .resting, let deadline = restUntil, seconds.isFinite, (1...300).contains(seconds),
              restDuration + seconds <= 3600 else { throw WorkoutError.invalidState(L10n.s("Rest cannot be extended further.")) }
        restUntil = deadline.addingTimeInterval(seconds); restDuration += seconds
    }

    public mutating func undoLastSet() throws {
        guard phase != .completed, activityTimer == nil else { throw WorkoutError.invalidState(L10n.s("Finish the running activity before undoing.")) }
        if let last = activities?.last, last.endedAt > (entries.last?.completedAt ?? .distantPast) {
            activities?.removeLast(); phase = .active; restUntil = nil; restDuration = 0
            transitionUntil = nil; transitionRemaining = nil; pendingTransition = nil
            var config = execution; config.order.removeAll { $0 == last.exerciseID }; config.order.insert(last.exerciseID, at: 0); configuration = config
            return
        }
        guard !entries.isEmpty else {
            throw WorkoutError.invalidState(L10n.s("There is no set to undo in this active workout."))
        }
        let removed = entries.removeLast()
        if configuration != nil {
            var config = execution; let original = originalID(for: removed.exerciseID)
            if config.substitutions.contains(where: { $0.originalID == removed.exerciseID && ($0.retainedSets ?? 0) > 0 }) {
                // Undoing the original-machine set crosses back before the
                // switch; no alternate set can remain after removing the last log.
                config.substitutions.removeAll { $0.originalID == removed.exerciseID }
                previousConfiguration = nil; adjustmentEntryCount = nil
                var changes = adjustments ?? []; if changes.count < 100 { changes.append(SessionAdjustment(id: UUID(), date: Date(), detail: L10n.s("Undid an original-machine set and its pending machine change."))) }; adjustments = changes
            }
            config.order.removeAll { $0 == original }; config.order.insert(original, at: 0); configuration = config
        }
        if effortResponse?.setID == removed.id { effortResponse = nil }
        transitionUntil = nil; transitionRemaining = nil; pendingTransition = nil
        phase = .active; restUntil = nil; restDuration = 0
    }

    public mutating func startActivity(now: Date = Date()) throws {
        guard phase == .active, activityTimer == nil, let exercise = currentExercise, exercise.kind != .strength, InputBoundary.validDate(now), now >= latestWorkDate else { throw WorkoutError.invalidState(L10n.s("This activity cannot start now.")) }
        activityTimer = ActivityTimer(exerciseID: exercise.id, spans: [ActivitySpan(start: now)])
    }
    public mutating func setActivityReadings(distance: Double?, speed: Double?, incline: Double?) throws {
        guard ActivityPrescription.valid(distance, 0...200_000), ActivityPrescription.valid(speed, 0...80), ActivityPrescription.valid(incline, -20...50), activityTimer != nil else { throw WorkoutError.invalidInput(L10n.s("Check the machine readings.")) }
        activityTimer?.distanceMeters = distance; activityTimer?.speedKph = speed; activityTimer?.inclinePercent = incline
    }
    public mutating func pauseActivity(now: Date = Date()) throws { guard activityTimer != nil else { return }; try activityTimer?.pause(at: now) }
    public mutating func resumeActivity(now: Date = Date()) throws { guard activityTimer != nil else { return }; try activityTimer?.resume(at: now) }
    public mutating func completeActivity(distanceMeters: Double? = nil, speedKph: Double? = nil, inclinePercent: Double? = nil, source: ValueSource = .user, now: Date = Date()) throws {
        guard var timer = activityTimer, let exercise = currentExercise, timer.exerciseID == exercise.id else { throw WorkoutError.invalidState(L10n.s("Start the activity before recording it.")) }
        if !timer.paused { try timer.pause(at: now) }
        let result = ActivityResult(id: UUID(), exerciseID: exercise.id, spans: timer.spans, endedAt: now, distanceMeters: distanceMeters ?? timer.distanceMeters, speedKph: speedKph ?? timer.speedKph, inclinePercent: inclinePercent ?? timer.inclinePercent, valuesSource: source, completed: true)
        try result.validate(start: startedAt, end: now)
        var records = activities ?? []; records.append(result); activities = records; activityTimer = nil
        if currentExercise == nil { finish(now: now) } else { pendingTransition = true; beginTransition(now: now) }
    }
    private mutating func beginTransition(now: Date) {
        guard pendingTransition == true else { return }; pendingTransition = nil
        guard let seconds = plan.transitionSeconds, seconds > 0, currentExercise != nil else { return }
        phase = .transitioning; transitionUntil = now.addingTimeInterval(Double(seconds)); transitionRemaining = nil
    }
    public mutating func skipTransition() {
        guard phase == .transitioning else { return }; phase = .active; transitionUntil = nil; transitionRemaining = nil
    }
    public mutating func pauseTransition(now: Date = Date()) {
        guard phase == .transitioning, let until = transitionUntil else { return }
        transitionRemaining = max(0, until.timeIntervalSince(now)); transitionUntil = nil
    }
    public mutating func resumeTransition(now: Date = Date()) {
        guard phase == .transitioning, let remaining = transitionRemaining else { return }
        transitionUntil = now.addingTimeInterval(remaining); transitionRemaining = nil
    }
    public mutating func extendTransition(now: Date = Date()) throws {
        guard phase == .transitioning else { return }
        if let until = transitionUntil { guard until.timeIntervalSince(now) < 600 else { return }; transitionUntil = max(until, now).addingTimeInterval(30) }
        if let remaining = transitionRemaining { transitionRemaining = min(600, remaining + 30) }
    }
    public mutating func skipExercise(reason: String, now: Date = Date()) throws {
        guard phase != .completed, activityTimer == nil, let exercise = currentExercise, !reason.isEmpty, reason.count <= 120 else { throw WorkoutError.invalidState(L10n.s("Stop the activity and give a short reason before skipping it.")) }
        var config = execution; config.skipped = Array(Set((config.skipped ?? []) + [originalID(for: exercise.id)]))
        try changeExecution(config, detail: L10n.s("Skipped remaining work: \(exercise.name). Reason: \(reason). Completed work preserved; skipped work is not completed."), now: now)
        if currentExercise == nil { finish(now: now) }
    }
    public mutating func chooseNext(_ id: UUID, now: Date = Date()) throws {
        guard activityTimer == nil, remainingExercises.contains(where: { originalID(for: $0.id) == id }) else { throw WorkoutError.invalidState(L10n.s("Choose a remaining exercise after stopping the activity.")) }
        var config = execution; config.order.removeAll { $0 == id }; config.order.insert(id, at: 0)
        try changeExecution(config, detail: L10n.s("Selected next exercise; original order and completed work preserved."), now: now)
    }

    public mutating func answerEffort(_ rating: Int?, now: Date = Date()) throws {
        guard let request = pendingEffort, let entry = entries.first(where: { $0.exerciseID == request.exerciseID && $0.setNumber == request.afterSet }),
              rating.map({ (1...10).contains($0) }) ?? true, now >= entry.completedAt, now.timeIntervalSince1970.isFinite else {
            throw WorkoutError.invalidInput(L10n.s("Choose an effort from 1–10, or skip the pending question."))
        }
        effortResponse = EffortResponse(requestID: request.id, setID: entry.id, rating: rating, recordedAt: now)
    }

    private mutating func changeExecution(_ next: ExecutionConfiguration, detail: String, now: Date) throws {
        guard phase != .completed, (adjustments?.count ?? 0) < 99 else { throw WorkoutError.invalidState(L10n.s("No more changes can be made in this session.")) }
        guard InputBoundary.validDate(now), now >= latestWorkDate else { throw WorkoutError.invalidInput(L10n.s("The workout change has an invalid timestamp.")) }
        let old = execution
        var candidate = self; candidate.configuration = next
        try candidate.validateExecution()
        candidate.previousConfiguration = old; candidate.adjustmentEntryCount = loggedWorkCount
        var log = adjustments ?? []; log.append(SessionAdjustment(id: UUID(), date: now, detail: detail)); candidate.adjustments = log
        try candidate.validateDeliveryReserve()
        self = candidate
    }
    public mutating func deferCurrent(now: Date = Date()) throws {
        guard activityTimer == nil, let current = currentExercise, remainingExercises.count > 1 else { throw WorkoutError.invalidState(L10n.s("No other exercise remains. Return when the machine is available.")) }
        let id = originalID(for: current.id); var next = execution
        next.order.removeAll { $0 == id }; next.order.append(id)
        try changeExecution(next, detail: L10n.s("Deferred \(current.name); completed sets and rest unchanged."), now: now)
    }
    public mutating func substituteCurrent(with alternativeID: UUID, reason: String = "Preference", proposeForFuture: Bool = false, now: Date = Date()) throws {
        guard activityTimer == nil, phase != .completed, let current = currentExercise, let original = plan.exercises.first(where: { $0.id == originalID(for: current.id) }),
              let alternative = original.alternatives?.first(where: { $0.id == alternativeID }), canSubstitute(with: alternative) else {
            throw WorkoutError.invalidInput(L10n.s("Choose an approved alternative in the same units. Once sets are logged on the alternative, defer or skip the remaining work instead."))
        }
        let retained = entries.filter { $0.exerciseID == original.id }.count
        var next = execution; next.substitutions.removeAll { $0.originalID == original.id }
        next.substitutions.append(Substitution(originalID: original.id, alternativeID: alternative.id, proposeForFuture: proposeForFuture, reason: String(reason.prefix(120)), retainedSets: retained == 0 ? nil : retained))
        try changeExecution(next, detail: L10n.s("\(proposeForFuture ? L10n.s("Proposed also for future review") : L10n.s("Today only")). Reason: \((reason == "Preference" ? L10n.s("Preference") : String(reason.prefix(120)))). Approved substitution: \(original.name) → \(alternative.name); \(alternative.reps) reps at \(Self.number(alternative.weight)) \(alternative.unit.rawValue), \(alternative.restSeconds)s prescribed rest. Original observation requests are not transferred to this variation."), now: now)
    }
    public mutating func omitOptional(_ ids: [UUID], now: Date = Date()) throws {
        let approved = Set(WorkoutPace.optionalCandidates(self).map { originalID(for: $0.id) })
        guard !ids.isEmpty, Set(ids).isSubset(of: approved), currentExercise.map({ !ids.contains(originalID(for: $0.id)) }) ?? false else {
            throw WorkoutError.invalidInput(L10n.s("Only untouched, approved optional work after the current exercise can be removed."))
        }
        var next = execution; next.omitted = Array(Set(next.omitted + ids))
        let names = plan.exercises.filter { ids.contains($0.id) }.map(\.name).joined(separator: ", ")
        try changeExecution(next, detail: L10n.s("Omitted approved optional work: \(names). Loads, repetitions, completed sets and required rest unchanged."), now: now)
    }
    public mutating func undoAdjustment(now: Date = Date()) throws {
        guard let previousConfiguration, adjustmentEntryCount == loggedWorkCount, phase != .completed else {
            throw WorkoutError.invalidState(L10n.s("This change can be reversed before another set is logged. Completed sets are never removed by reversing a plan change."))
        }
        var candidate = self; candidate.configuration = previousConfiguration; try candidate.validateExecution()
        candidate.previousConfiguration = nil; candidate.adjustmentEntryCount = nil
        var log = adjustments ?? []; log.append(SessionAdjustment(id: UUID(), date: now, detail: L10n.s("Reversed the last workout change before logging another set."))); candidate.adjustments = log
        try candidate.validateDeliveryReserve(); self = candidate
    }

    public mutating func finish(now: Date = Date(), resolveEffort: Bool = true) {
        guard phase != .completed else { return }
        if var timer = activityTimer {
            let stop = max(now, timer.spans.last?.start ?? startedAt)
            if !timer.paused { try? timer.pause(at: stop) }
            var records = activities ?? []
            records.append(ActivityResult(id: UUID(), exerciseID: timer.exerciseID, spans: timer.spans, endedAt: stop, distanceMeters: timer.distanceMeters, speedKph: timer.speedKph, inclinePercent: timer.inclinePercent, valuesSource: .machine, completed: false))
            activities = records; activityTimer = nil
        }
        if resolveEffort, let request = pendingEffort, let entry = entries.last(where: { $0.exerciseID == request.exerciseID }) {
            effortResponse = EffortResponse(requestID: request.id, setID: entry.id, rating: nil, recordedAt: max(now, entry.completedAt))
        }
        phase = .completed; endedAt = max(now, latestWorkDate, startedAt); hydrationDue = nil
        restUntil = nil; restDuration = 0; transitionUntil = nil; transitionRemaining = nil; pendingTransition = nil
    }

    public func validateCompleted() throws {
        try plan.validate()
        try validateEffort()
        try validateExecution()
        guard appliedCorrections == nil, isReadyForDelivery, let end = endedAt, end >= startedAt,
              InputBoundary.validDate(startedAt), InputBoundary.validDate(end),
              entries.count <= plan.totalSets, Set(entries.map(\.id)).count == entries.count else {
            throw WorkoutError.invalidInput(L10n.s("The received workout is incomplete or invalid."))
        }
        guard activityTimer == nil, (activities?.count ?? 0) <= plan.exercises.count, Set((activities ?? []).map(\.id)).count == (activities?.count ?? 0), Set((activities ?? []).map(\.exerciseID)).count == (activities?.count ?? 0) else { throw WorkoutError.invalidInput(L10n.s("Duplicate or unfinished activity.")) }
        for activity in activities ?? [] {
            guard executionExercises.contains(where: { $0.id == activity.exerciseID && $0.kind != .strength }) else { throw WorkoutError.invalidInput(L10n.s("Activity does not match its prescription.")) }
            try activity.validate(start: startedAt, end: end)
        }
        var seen = Set<String>()
        var previousDate = startedAt
        var counts: [UUID: Int] = [:]
        for entry in entries {
            guard let exercise = executionExercises.first(where: { $0.id == entry.exerciseID }),
                  exercise.kind == .strength, (1...exercise.sets).contains(entry.setNumber), (1...200).contains(entry.reps),
                  entry.weight.isFinite, (0...1000).contains(entry.weight),
                  entry.completedAt >= previousDate, entry.completedAt <= end,
                  entry.setNumber == (counts[entry.exerciseID] ?? 0) + 1,
                  entry.loggedUptime.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  seen.insert("\(entry.exerciseID)-\(entry.setNumber)").inserted else {
                throw WorkoutError.invalidInput(L10n.s("A received set has invalid or duplicate values."))
            }
            previousDate = entry.completedAt
            counts[entry.exerciseID] = entry.setNumber
        }
    }

    public func report() -> String {
        let date = ISO8601DateFormatter().string(from: startedAt)
        var lines = [L10n.s("WORKOUT LOG"), L10n.s("Session ID: \(id.uuidString)"), L10n.s("Date: \(date)"),
                     L10n.s("Workout: \(plan.title)"), L10n.s("Duration: \(Int(duration / 60)) min"),
                     L10n.s("Completed: \(loggedWorkCount) / \(plan.totalSets) sets / segments"), L10n.s("Units: \(plan.unit.rawValue)"), ""]
        if let correctionSummary { lines.append(correctionSummary) }
        if plan.practice == true { lines.append(L10n.s("PRACTICE SESSION — excluded from weekly goals; not evidence of training progression.")) }
        for exercise in executionExercises {
            lines.append(exercise.name)
            if let activity = exercise.activity {
                lines.append(L10n.s("  Prescribed: \(activity.summary)"))
                if let result = activities?.first(where: { $0.exerciseID == exercise.id }) { lines.append(L10n.s("  Recorded: \(result.summary(unit: activity.distanceUnit))")) }
                else { lines.append(L10n.s("  Not completed; results unavailable")) }
                continue
            }
            if (execution.skipped ?? []).contains(originalID(for: exercise.id)) { lines.append(L10n.s("  Remaining work skipped; not completed")) }
            lines.append(L10n.s("  Prescribed: \(exercise.prescription(unit: plan.unit))"))
            lines.append(L10n.s("  Load convention: \(exercise.loadConvention?.label ?? L10n.s("unspecified; cross-workout comparison unavailable"))"))
            lines.append(L10n.s("  Variation ID: \(exercise.comparisonID ?? L10n.s("unspecified"))"))
            let logged = entries.filter { $0.exerciseID == exercise.id }
            if logged.isEmpty { lines.append(L10n.s("  Not completed")) }
            for entry in logged {
                lines.append(L10n.s("  Set \(entry.setNumber) (user-confirmed): \(Self.number(entry.weight)) \(plan.unit.rawValue) × \(entry.reps) reps"))
            }
        }
        if let adjustments, !adjustments.isEmpty {
            lines.append(L10n.s("\nEXPLICIT WORKOUT CHANGES (original prescription preserved)"))
            for change in adjustments { lines.append(change.detail) }
            for original in plan.exercises { lines.append(L10n.s("Original: \(original.name) · \(original.prescription(unit: plan.unit))")) }
        }
        if !observationEvidence.isEmpty {
            lines.append(L10n.s("\nCOACH OBSERVATIONS"))
            for evidence in observationEvidence {
                lines.append(L10n.s("[\(evidence.requestID)] \(evidence.title) · Set ID: \(evidence.setID?.uuidString ?? L10n.s("not logged"))\n\(evidence.detail)"))
            }
        }
        lines.append(L10n.s("\nPlease log these actual results and give descriptive feedback. Do not treat uncompleted sets as completed. Compare across workouts only when variation IDs, units and load conventions match; otherwise explain insufficient data. Log-tap intervals include exercise time and do not measure actual rest. Strength sets have no physical start/end or motion measurements. Timed activities report explicit Start/Pause/Resume/Done events, not sensor measurements. Do not infer causation, injury risk or medical readiness. Propose any next plan for my review; never assume it has been accepted."))
        return lines.joined(separator: "\n")
    }

    public static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: L10n.language)))
    }
}

public struct TrainingReview: Codable, Equatable, Sendable {
    public let analysis: String
    public let plan: WorkoutPlan
    public init(analysis: String, plan: WorkoutPlan) { self.analysis = analysis; self.plan = plan }
}
public struct UnlinkedCoachReview: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let response: TrainingReview
    public let savedAt: Date
}

public enum ConnectionMode: String, Codable, CaseIterable, Sendable {
    case existingChat, shortcut
    public var title: String { self == .existingChat ? L10n.s("My existing chat") : L10n.s("Review Shortcut") }
}

public struct PhoneState: Codable, Equatable, Sendable {
    public var storageVersion: Int? = 2
    public var plan: WorkoutPlan?
    public var sessions: [WorkoutSession] = []
    public var setCorrections: [SetCorrection]?
    public var lastWatchReceipt: WatchPlanReceipt?
    public var unlinkedCoachReviewsOutdatedAt: Date?
    public var comfort: ComfortPreferences?
    public var weeklyHabit: WeeklyHabit?
    public var onboardingSteps: [String]?
    public var equipmentContext: String?
    public var contextProfileApproved: Bool?
    public var contextHistoryApproved: Bool?
    public var profile = ""
    public var mode: ConnectionMode = .existingChat
    public var review: TrainingReview?
    public var unlinkedCoachReviews: [UnlinkedCoachReview]?
    public var routines: [Routine]?
    public var schedule: [WeeklySlot]?
    public var importedHistory: [HistoricalWorkout]?
    public var reviewJobs: [ReviewJob]?
    public var coachConnectionCheck: CoachConnectionCheck?
    public var chatHandoff: ChatHandoff?
    public var reviewNotificationsEnabled: Bool?
    public var selectedReviewSessionID: UUID?
    public var doubleTapEnabled: Bool?
    public var motionOptIn: Bool?
    public var motionExercise: MotionExercise?
    public init() {}

    public mutating func propose(_ review: TrainingReview) throws {
        try review.plan.validate()
        guard self.review == nil || self.review == review else {
            throw WorkoutError.invalidState(L10n.s("Review or discard the current proposal first. Your saved coach responses remain in History."))
        }
        self.review = review
    }
    public mutating func acceptReview() throws {
        guard let review else { return }
        try review.plan.validate(); archiveUnlinkedReview(); plan = review.plan; self.review = nil
    }
    public mutating func discardReview() {
        archiveUnlinkedReview(); review = nil
    }
    private mutating func archiveUnlinkedReview() {
        guard let review, !reviewQueue.contains(where: { $0.result == review }),
              !(unlinkedCoachReviews ?? []).contains(where: { $0.response == review }) else { return }
        var saved = unlinkedCoachReviews ?? []
        saved.append(UnlinkedCoachReview(id: UUID(), response: review, savedAt: Date()))
        unlinkedCoachReviews = saved
    }

    public mutating func receive(_ session: WorkoutSession) throws {
        try session.validateCompleted()
        if let original = sessions.first(where: { $0.id == session.id }) {
            guard original == session else {
                throw WorkoutError.invalidInput(L10n.s("A different workout already has this ID. The saved original was preserved; the conflicting delivery was not acknowledged."))
            }
            return
        }
        sessions.append(session); sessions.sort { $0.startedAt > $1.startedAt }
        queueReview(for: session.id)
    }
}

public struct WatchState: Codable, Equatable, Sendable {
    public var storageVersion: Int? = 2
    public var plan: WorkoutPlan?
    public var session: WorkoutSession?
    public var outbox: [WorkoutSession] = []
    public var recent: [WorkoutSession] = []
    public var comfort: ComfortPreferences?
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
    public let comfort: ComfortPreferences?
    public let doubleTapEnabled: Bool?
    public let motionOptIn: Bool?
    public let motionExercise: MotionExercise?
    public init(plan: WorkoutPlan?, acknowledged: [UUID], issuedAt: Date = Date(), doubleTapEnabled: Bool? = nil, motionOptIn: Bool? = nil, motionExercise: MotionExercise? = nil, comfort: ComfortPreferences? = nil) {
        self.comfort = comfort
        self.motionExercise = motionExercise
        self.motionOptIn = motionOptIn
        self.doubleTapEnabled = doubleTapEnabled
        self.plan = plan; self.acknowledged = acknowledged; self.issuedAt = issuedAt
    }
    private enum CodingKeys: String, CodingKey { case plan, acknowledged, issuedAt, doubleTapEnabled, motionOptIn, motionExercise, comfort }
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        comfort = try fields.decodeIfPresent(ComfortPreferences.self, forKey: .comfort)
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
