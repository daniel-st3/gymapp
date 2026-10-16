import Foundation

/// Untrusted extraction stays a draft. Empty fields are questions, never defaults.
public struct DraftExercise: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name = ""
    public var sets = ""
    public var reps = ""
    public var weight = ""
    public var rest = ""
    public var unit = ""
    public var convention = ""
    public var comparisonID = ""
    public var source = ""
    public var optionalWork = false
    public var hasPolicy = false
    public var priority = 3
    public init() {}
    public init(_ exercise: ExercisePlan, unit: WeightUnit) {
        id = exercise.id; name = exercise.name; sets = String(exercise.sets); reps = String(exercise.reps)
        weight = String(exercise.weight); rest = String(exercise.restSeconds); self.unit = unit.rawValue
        convention = exercise.loadConvention?.rawValue ?? ""; comparisonID = exercise.comparisonID ?? ""
        optionalWork = exercise.workPolicy?.optional ?? false; priority = exercise.workPolicy?.priority ?? 3; hasPolicy = exercise.workPolicy != nil
    }
    public func exercise() throws -> ExercisePlan {
        guard let sets = Int(sets), let reps = Int(reps), let weight = Double(weight.replacingOccurrences(of: ",", with: ".")),
              let rest = Int(rest), WeightUnit(rawValue: unit) != nil else {
            throw WorkoutError.invalidInput("Complete sets, repetitions, load, kg/lb and rest for \(name.isEmpty ? "each exercise" : name). Ranges need an explicit target; no missing values are assumed.")
        }
        guard convention.isEmpty || LoadConvention(rawValue: convention) != nil else {
            throw WorkoutError.invalidInput("Choose a supported load convention.")
        }
        var result = ExercisePlan(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), sets: sets, reps: reps, weight: weight, restSeconds: rest,
            comparisonID: comparisonID.isEmpty ? nil : comparisonID, loadConvention: convention.isEmpty ? nil : LoadConvention(rawValue: convention))
        if hasPolicy || optionalWork || priority != 3 { result.workPolicy = WorkPolicy(priority: priority, optional: optionalWork) }
        return result
    }
}

public struct WorkoutDraft: Equatable, Sendable {
    public var title = ""
    public var exercises: [DraftExercise] = []
    public var source = ""
    public var notes: [String] = []
    public var original: WorkoutPlan?
    public init() {}
    public init(plan: WorkoutPlan) {
        original = plan; title = plan.title; exercises = plan.exercises.map { DraftExercise($0, unit: plan.unit) }
    }
    /// Called only after explicit removal approval in the editor. No saved plan
    /// or completed session is modified; linked requests cannot become dangling.
    public mutating func removeExercise(_ id: UUID) {
        exercises.removeAll { $0.id == id }
        original?.observations?.removeAll { $0.exerciseID == id }
    }
    public func validated() throws -> WorkoutPlan {
        guard Set(exercises.map(\.unit)).count == 1, let unit = exercises.first.flatMap({ WeightUnit(rawValue: $0.unit) }) else {
            throw WorkoutError.invalidInput("Choose kg or lb for every exercise. Mixed units must be split into separate workouts; the app does not convert them silently.")
        }
        var plan = original ?? WorkoutPlan(title: title, unit: unit, exercises: [])
        plan.title = title; plan.unit = unit; plan.exercises = try exercises.map { draft in
            var exercise = try draft.exercise()
            exercise.alternatives = original?.exercises.first(where: { $0.id == draft.id })?.alternatives
            return exercise
        }
        try plan.validate(); return plan
    }
}

public enum SmartWorkoutImport {
    public static func extract(_ text: String) throws -> WorkoutDraft {
        guard text.utf8.count <= 64_000 else { throw WorkoutError.invalidInput("Import at most 64 KB at a time.") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("```") {
            return WorkoutDraft(plan: try PlanImport.parse(text))
        }
        var draft = WorkoutDraft(); draft.source = text
        draft.notes = ["Check every extracted field against the source. Missing values and ranges require your decision. A load convention and exact variation ID enable later comparisons; leave both blank when unknown."]
        for raw in trimmed.components(separatedBy: .newlines).filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("workout:") || line.lowercased().hasPrefix("title:") {
                draft.title = String(line.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces); continue
            }
            var row = DraftExercise(); row.source = line
            let pattern = #"(?i)(\d+)\s*(?:x|×|sets?\s*(?:of)?)\s*(\d+)(?!\d)(?:\s*reps?)?"#
            if let match = first(pattern, line) {
                row.sets = match.1[0]; row.reps = match.1[1]
                row.name = String(line[..<match.0.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " -–—:•\t"))
                if line.range(of: #"\d\s*[-–]\s*\d"#, options: .regularExpression) != nil {
                    row.reps = ""; draft.notes.append("A range in “\(row.name)” needs a single confirmed target.")
                }
            } else { row.name = line }
            if let load = first(#"(?i)(?<![-\d.,])(\d+(?:[.,]\d+)?)\s*(kg|lb)\b"#, line) {
                row.weight = load.1[0]; row.unit = load.1[1].lowercased()
            }
            if let rest = first(#"(?i)rest\s*[:=]?\s*(\d+)\s*(s|sec(?:onds?)?|min(?:utes?)?)\b"#, line), let n = Int(rest.1[0]) {
                row.rest = String(n * (rest.1[1].lowercased().hasPrefix("min") ? 60 : 1))
            }
            // A displayed convention without an explicit variation ID remains a
            // draft question. It is never converted into an invented identity.
            row.convention = explicitConvention(in: line)
            if draft.title.isEmpty && row.sets.isEmpty && draft.exercises.isEmpty && !line.contains(where: \.isNumber) {
                draft.title = line
            } else { draft.exercises.append(row) }
        }
        if draft.exercises.isEmpty { draft.exercises = [DraftExercise()] }
        guard draft.exercises.count <= 50 else { throw WorkoutError.invalidInput("Import at most 50 exercise lines.") }
        return draft
    }
    public static func explicitConvention(in text: String) -> String {
        let phrases: [(String, String)] = [("per dumbbell", "perDumbbell"), ("machine stack", "machineStack"), ("total load", "total"), ("total external load", "total"), ("assistance setting", "assistance"), ("bodyweight", "bodyweight")]
        let found = Set(phrases.filter { text.localizedCaseInsensitiveContains($0.0) }.map(\.1))
        return found.count == 1 ? found.first! : ""
    }
    public static func cleanExtractedNumber(_ text: String, kind: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == "rest", let m = first(#"(?i)^(\d+)\s*(s|sec(?:onds?)?|min(?:utes?)?)$"#, value), let n = Int(m.1[0]) {
            return String(n * (m.1[1].lowercased().hasPrefix("min") ? 60 : 1))
        }
        let suffix = kind == "weight" ? "(?:kg|lb)?" : "(?:sets?|reps?)?"
        if let m = first("(?i)^(\\d+(?:[.,]\\d+)?)\\s*" + suffix + "$", value) { return m.1[0] }
        return value // leave ranges and unsupported values visibly unresolved
    }
    private static func first(_ pattern: String, _ text: String) -> (Range<String.Index>, [String])? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(m.range, in: text) else { return nil }
        return (range, (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" })
    }
}
