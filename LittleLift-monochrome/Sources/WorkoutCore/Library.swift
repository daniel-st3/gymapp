import Foundation

public struct WorkPolicy: Codable, Equatable, Sendable {
    public var priority: Int
    public var optional: Bool
    public init(priority: Int, optional: Bool) { self.priority = priority; self.optional = optional }
}
public struct Routine: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var plan: WorkoutPlan
    public var previousVersions: [WorkoutPlan]
    public init(plan: WorkoutPlan) { id = UUID(); self.plan = plan; previousVersions = [] }
}
public struct WeeklySlot: Codable, Equatable, Identifiable, Sendable {
    public var weekday: Int
    public var routineID: UUID
    public var id: Int { weekday }
    public init(weekday: Int, routineID: UUID) { self.weekday = weekday; self.routineID = routineID }
}

/// External records never masquerade as sensor or Log-tap observations.
public struct HistoricalWorkout: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: String
    public let title: String
    public let source: String
    public let unit: WeightUnit
    public let exercises: [HistoricalExercise]
    public var parsedDate: Date? { ISO8601DateFormatter().date(from: date) }
    public func validate() throws {
        guard let day = parsedDate, day <= Date().addingTimeInterval(86400), title.count <= 120, !title.isEmpty,
              !source.isEmpty, source.count <= 240, (1...50).contains(exercises.count) else {
            throw WorkoutError.invalidInput(L10n.s("History needs a stable UUID id, past ISO date, title, source and 1–50 exercises."))
        }
        for exercise in exercises {
            guard !exercise.name.isEmpty, exercise.name.count <= 120, (1...20).contains(exercise.sets.count),
                  exercise.sets.allSatisfy({ (1...200).contains($0.reps) && $0.weight.isFinite && (0...1000).contains($0.weight) }),
                  (exercise.comparisonID == nil) == (exercise.loadConvention == nil), exercise.comparisonID.map(WorkoutPlan.validIdentifier) ?? true else {
                throw WorkoutError.invalidInput(L10n.s("Imported history must contain actual set values, with valid matching metadata if supplied. Targets alone are not a completed workout."))
            }
        }
    }
    public func report() -> String {
        var lines = [L10n.s("IMPORTED HISTORY — user-confirmed external record"), L10n.s("ID: \(id)"), L10n.s("\(date) · \(title) · source: \(source)"), L10n.s("No Little Lift timestamps, effort or sensor observations collected.")]
        for e in exercises {
            lines.append("\(e.name) [\(e.comparisonID ?? L10n.s("unmatched"))] · \(e.loadConvention?.label ?? L10n.s("convention unspecified"))")
            lines += e.sets.enumerated().map { L10n.s("Set \($0.offset + 1): \(WorkoutSession.number($0.element.weight)) \(unit.rawValue) × \($0.element.reps) reps (imported actual)") }
        }
        return lines.joined(separator: "\n")
    }
}
public struct HistoricalExercise: Codable, Equatable, Sendable {
    public let name: String
    public let comparisonID: String?
    public let loadConvention: LoadConvention?
    public let sets: [HistoricalSet]
}
public struct HistoricalSet: Codable, Equatable, Sendable { public let weight: Double; public let reps: Int }

public enum HistoryImport {
    public static func parse(_ text: String) throws -> [HistoricalWorkout] {
        guard text.utf8.count <= 256_000 else { throw WorkoutError.invalidInput(L10n.s("Import at most 256 KB of history at once.")) }
        let rows: [HistoricalWorkout]
        try JSONBoundary.validate(Data(text.utf8))
        do { rows = try JSONDecoder().decode([HistoricalWorkout].self, from: Data(text.utf8)) }
        catch { throw WorkoutError.invalidInput(L10n.s("Use the history example schema: an array of records with stable UUID id, ISO date, title, source, unit and actual exercise sets.")) }
        guard (1...100).contains(rows.count), Set(rows.map(\.id)).count == rows.count else { throw WorkoutError.invalidInput(L10n.s("Import 1–100 records with unique IDs.")) }
        try rows.forEach { try $0.validate() }; return rows
    }
    public static let example = """
    [{"id":"22222222-2222-4222-8222-222222222222","date":"2026-10-01T12:00:00Z","title":"Example historical workout","source":"My confirmed training notes","unit":"kg","exercises":[{"name":"Seated row","comparisonID":"row-machine-a-neutral","loadConvention":"machineStack","sets":[{"weight":30,"reps":10},{"weight":30,"reps":9}]}]}]
    """
}

extension PhoneState {
    public var routineLibrary: [Routine] { routines ?? [] }
    public var weeklySchedule: [WeeklySlot] { schedule ?? [] }
    public var externalHistory: [HistoricalWorkout] { importedHistory ?? [] }
    @discardableResult
    public mutating func saveRoutine(_ plan: WorkoutPlan, replacing id: UUID? = nil) throws -> WorkoutPlan {
        try plan.validate()
        var all = routineLibrary
        let saved: WorkoutPlan
        if let id {
            guard let i = all.firstIndex(where: { $0.id == id }) else { throw WorkoutError.invalidInput(L10n.s("This routine is no longer available. Reopen the library before saving.")) }
            if all[i].plan == plan { return all[i].plan }
            guard all[i].previousVersions.count < 100 else { throw WorkoutError.invalidInput(L10n.s("This routine has 100 saved revisions. Save a new routine to preserve the archive.")) }
            all[i].previousVersions.append(all[i].plan)
            var revision = plan; revision.id = UUID(); all[i].plan = revision
            saved = revision
        } else {
            if let existing = all.first(where: { $0.plan == plan }) { return existing.plan }
            guard all.count < 100 else { throw WorkoutError.invalidInput(L10n.s("The library supports up to 100 routines.")) }
            var unique = plan
            if all.contains(where: { $0.plan.id == plan.id || $0.previousVersions.contains(where: { $0.id == plan.id }) }) { unique.id = UUID() }
            all.append(Routine(plan: unique)); saved = unique
        }
        routines = all
        return saved
    }
    /// One transaction keeps Today on the exact saved revision. A failure cannot
    /// leave a library edit half-saved or add a second copy of that revision.
    public mutating func saveWorkout(_ plan: WorkoutPlan, replacing id: UUID? = nil, useToday: Bool) throws {
        var next = self
        if useToday, let previous = next.plan, previous != plan,
           !next.routineLibrary.contains(where: { $0.plan == previous || $0.previousVersions.contains(previous) }) {
            _ = try next.saveRoutine(previous)
        }
        let saved = try next.saveRoutine(plan, replacing: id)
        if useToday { next.plan = saved }
        self = next
    }
    public mutating func scheduleRoutine(_ id: UUID?, weekday: Int) throws {
        guard (1...7).contains(weekday), id == nil || routineLibrary.contains(where: { $0.id == id }) else { throw WorkoutError.invalidInput(L10n.s("Choose an existing routine and weekday.")) }
        var slots = weeklySchedule.filter { $0.weekday != weekday }
        if let id { slots.append(WeeklySlot(weekday: weekday, routineID: id)) }
        schedule = slots.sorted { $0.weekday < $1.weekday }
    }
    public mutating func importHistory(_ records: [HistoricalWorkout]) throws {
        try records.forEach { try $0.validate() }
        var all = externalHistory
        for record in records {
            if let old = all.first(where: { $0.id == record.id }) {
                guard old == record else { throw WorkoutError.invalidInput(L10n.s("A history ID already exists with different values. Original records are preserved.")) }
            } else if !all.contains(where: { $0.date == record.date && $0.title == record.title && $0.unit == record.unit && $0.exercises == record.exercises }) { all.append(record) }
        }
        importedHistory = all.sorted { ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast) }
    }
    public func contextExport() -> String {
        let shareHistory = contextHistoryApproved != false
        let actual = (shareHistory ? effectiveSessions : []).sorted { $0.startedAt > $1.startedAt }.prefix(8).map { $0.report() }.joined(separator: "\n---\n")
        let external = (shareHistory ? externalHistory : []).prefix(8).map { $0.report() }.joined(separator: "\n---\n")
        let routines = routineLibrary.prefix(12).map { L10n.s("\($0.plan.title): \($0.plan.totalSets) prescribed sets / segments; not completed history") }.joined(separator: "\n")
        let progression = shareHistory ? Progression.summary(effectiveSessions) : L10n.s("Not shared")
        let lines = [
            L10n.s("LITTLE LIFT CONTEXT — explicit export for my chosen chat"),
            L10n.s("USER-EDITABLE PROFILE / PREFERENCES"),
            contextProfileApproved == true ? profile : L10n.s("Profile not shared; ask before requesting personal details."),
            L10n.s("KNOWN EQUIPMENT / OPTIONAL GYM CONTEXT (user supplied, not independently verified)"),
            equipmentContext ?? L10n.s("Not supplied"),
            L10n.s("If web search is available in the chosen chat, use official sources and ask me to confirm a machine/branch match. A description is not a verified inventory. Do not change a variation or load from a search result."),
            L10n.s("RECENT CONFIRMED LITTLE LIFT LOGS (up to 8 of \(sessions.count))"),
            actual.isEmpty ? L10n.s("None shared") : actual,
            L10n.s("EXTERNAL HISTORY (up to 8 of \(externalHistory.count)); user-confirmed, not measured by Little Lift"),
            external.isEmpty ? L10n.s("None shared") : external,
            L10n.s("MATCHED PROGRESSION (latest workout versus most recent matching results)"), progression,
            L10n.s("SAVED ROUTINES (prescriptions only)"), routines,
            L10n.s("No previous conversation is assumed. Missing values are unknown. Keep variation, units and load conventions matched. No causal, injury-risk or medical-readiness conclusions. Any proposed plan requires my acceptance.")
        ]
        let text = lines.joined(separator: "\n")
        if text.count > 40_000 { return String(text.prefix(40_000)) + "\n" + L10n.s("Context truncated at 40,000 characters; request selected older reports if needed.") }
        return text
    }
}
public enum Progression {
    /// Only actual logged sets of the exact variation qualify. Imported history,
    /// uncompleted prescriptions and similarly named machines are not evidence.
    public static func lastResult(for exercise: ExercisePlan, unit: WeightUnit, sessions: [WorkoutSession]) -> (session: WorkoutSession, entry: CompletedSet)? {
        for session in sessions.sorted(by: { $0.startedAt > $1.startedAt }) where session.phase == .completed && session.plan.practice != true {
            let matchingIDs = Set(session.executionExercises.filter { $0.matches(exercise, unit: session.plan.unit, otherUnit: unit) }.map(\.id))
            if let entry = session.entries.last(where: { matchingIDs.contains($0.exerciseID) }) { return (session, entry) }
        }
        return nil
    }
    public static func summary(_ sessions: [WorkoutSession]) -> String {
        let sorted = sessions.filter { $0.phase == .completed && $0.plan.practice != true }.sorted { $0.startedAt > $1.startedAt }
        guard let latest = sorted.first else { return L10n.s("Insufficient confirmed history.") }
        var lines: [String] = []
        for exercise in latest.executionExercises {
            guard let current = latest.entries.last(where: { $0.exerciseID == exercise.id }) else { continue }
            var found = false
            for old in sorted.dropFirst() {
                guard let match = old.executionExercises.first(where: { $0.matches(exercise, unit: old.plan.unit, otherUnit: latest.plan.unit) }), let prior = old.entries.last(where: { $0.exerciseID == match.id }) else { continue }
                lines.append(L10n.s("\(exercise.name), final logged set: \(WorkoutSession.number(prior.weight)) × \(prior.reps) → \(WorkoutSession.number(current.weight)) × \(current.reps) \(latest.plan.unit.rawValue). \(exercise.loadConvention?.label ?? "") No cause inferred."))
                found = true; break
            }
            if !found { lines.append(L10n.s("\(exercise.name): insufficient matching variation/unit/convention history.")) }
        }
        return lines.isEmpty ? L10n.s("Insufficient logged sets.") : lines.joined(separator: "\n")
    }
}
