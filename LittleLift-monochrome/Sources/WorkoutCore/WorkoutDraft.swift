import Foundation

/// Untrusted extraction stays a draft. Empty fields are questions, never defaults.
public struct DraftExercise: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: ActivityKind?
    public var durationMinutes = ""
    public var distance = ""
    public var distanceUnit: DistanceUnit = .km
    public var speed = ""
    public var incline = ""
    public var addedLoad = ""
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
        kind = exercise.kind
        if let a = exercise.activity {
            durationMinutes = a.durationSeconds.map { String($0 / 60) } ?? ""
            distanceUnit = a.distanceUnit; distance = a.distanceMeters.map { String($0 / a.distanceUnit.meters) } ?? ""
            speed = a.speedKph.map { String($0 / (a.distanceUnit == .mi ? 1.609344 : 1)) } ?? ""
            incline = a.inclinePercent.map(String.init(describing:)) ?? ""; addedLoad = a.additionalLoad.map(String.init(describing:)) ?? ""
        }
        id = exercise.id; name = exercise.name; sets = String(exercise.sets); reps = String(exercise.reps)
        weight = String(exercise.weight); rest = String(exercise.restSeconds); self.unit = unit.rawValue
        convention = exercise.loadConvention?.rawValue ?? ""; comparisonID = exercise.comparisonID ?? ""
        optionalWork = exercise.workPolicy?.optional ?? false; priority = exercise.workPolicy?.priority ?? 3; hasPolicy = exercise.workPolicy != nil
    }
    public func exercise() throws -> ExercisePlan {
        let selected = kind ?? (!sets.isEmpty && !reps.isEmpty ? .strength : nil)
        guard let selected else { throw WorkoutError.invalidInput(L10n.s("Choose an activity type for this ambiguous exercise.")) }
        if selected != .strength {
            var result = ExercisePlan(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), sets: 1, reps: 1, weight: 0, restSeconds: 0)
            result.activity = ActivityPrescription(kind: selected, durationSeconds: try Self.optionalNumber(durationMinutes).map { $0 * 60 }, distanceMeters: try Self.optionalNumber(distance).map { $0 * distanceUnit.meters }, speedKph: try Self.optionalNumber(speed).map { $0 * (distanceUnit == .mi ? 1.609344 : 1) }, inclinePercent: try Self.optionalNumber(incline), distanceUnit: distanceUnit, additionalLoad: try Self.optionalNumber(addedLoad))
            try result.activity?.validate()
            if hasPolicy || optionalWork || priority != 3 { result.workPolicy = WorkPolicy(priority: priority, optional: optionalWork) }
            return result
        }
        guard let sets = Int(sets), let reps = Int(reps), let weight = Double(weight.replacingOccurrences(of: ",", with: ".")),
              let rest = Int(rest), WeightUnit(rawValue: unit) != nil else {
            throw WorkoutError.invalidInput(L10n.s("Complete sets, repetitions, load, kg/lb and rest for \(name.isEmpty ? "each exercise" : name). Ranges need an explicit target; no missing values are assumed."))
        }
        guard convention.isEmpty || LoadConvention(rawValue: convention) != nil else {
            throw WorkoutError.invalidInput(L10n.s("Choose a supported load convention."))
        }
        var result = ExercisePlan(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), sets: sets, reps: reps, weight: weight, restSeconds: rest,
            comparisonID: comparisonID.isEmpty ? nil : comparisonID, loadConvention: convention.isEmpty ? nil : LoadConvention(rawValue: convention))
        if hasPolicy || optionalWork || priority != 3 { result.workPolicy = WorkPolicy(priority: priority, optional: optionalWork) }
        return result
    }
    private static func optionalNumber(_ text: String) throws -> Double? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite else { throw WorkoutError.invalidInput(L10n.s("Enter a number or leave unknown values empty.")) }
        return value
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
        let weighted = exercises.filter { $0.kind == .strength || ($0.kind == nil && !$0.sets.isEmpty) || !$0.addedLoad.isEmpty }
        guard Set(weighted.map(\.unit)).count <= 1, weighted.allSatisfy({ WeightUnit(rawValue: $0.unit) != nil }) else {
            throw WorkoutError.invalidInput(L10n.s("Choose kg or lb for every exercise. Mixed units must be split into separate workouts; the app does not convert them silently."))
        }
        let unit = weighted.first.flatMap { WeightUnit(rawValue: $0.unit) } ?? original?.unit ?? .kg
        var plan = original ?? WorkoutPlan(title: title, unit: unit, exercises: [])
        plan.title = title; plan.unit = unit; plan.exercises = try exercises.map { draft in
            var exercise = try draft.exercise()
            exercise.alternatives = original?.exercises.first(where: { $0.id == draft.id })?.alternatives
            return exercise
        }
        if plan.exercises.contains(where: { $0.activity != nil }) { plan.schemaVersion = 2 }
        try plan.validate(); return plan
    }
}

public enum SmartWorkoutImport {
    public static func extract(_ text: String) throws -> WorkoutDraft {
        guard text.utf8.count <= 64_000 else { throw WorkoutError.invalidInput(L10n.s("Import at most 64 KB at a time.")) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("```") {
            return WorkoutDraft(plan: try PlanImport.parse(text))
        }
        var draft = WorkoutDraft(); draft.source = text
        draft.notes = [L10n.s("Check every extracted field against the source. Missing values and ranges require your decision. A load convention and exact variation ID enable later comparisons; leave both blank when unknown.")]
        for raw in trimmed.components(separatedBy: .newlines).filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("workout:") || line.lowercased().hasPrefix("title:") || line.lowercased().hasPrefix("entrenamiento:") {
                draft.title = String(line.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces); continue
            }
            var row = DraftExercise(); row.source = line
            let lower = line.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            if lower.range(of: #"\b(caminar|caminata|caminadora|walking|walk|treadmill|correr|running|run|movilidad|mobility)\b"#, options: .regularExpression) != nil {
                row.kind = lower.contains("correr") || lower.contains("running") || lower.hasPrefix("run ") ? .running : (lower.contains("movilidad") || lower.contains("mobility") ? .mobility : .walking)
                row.name = line.components(separatedBy: CharacterSet.decimalDigits).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? line
                if let duration = first(#"(?i)(\d+(?:[.,]\d+)?)\s*(?:min|minutes|minutos)\b"#, line) { row.durationMinutes = duration.1[0] }
                if let speed = first(#"(?i)(\d+(?:[.,]\d+)?)\s*(km/h|kph|mph)\b"#, line) { row.speed = speed.1[0]; row.distanceUnit = speed.1[1].lowercased() == "mph" ? .mi : .km }
                if let distance = first(#"(?i)(\d+(?:[.,]\d+)?)\s*(km|mi)(?!/h)\b"#, line) { row.distance = distance.1[0]; row.distanceUnit = distance.1[1].lowercased() == "mi" ? .mi : .km }
                if let incline = first(#"(-?\d+(?:[.,]\d+)?)\s*%"#, line) { row.incline = incline.1[0] }
                if let load = first(#"(?i)(\d+(?:[.,]\d+)?)\s*(kg|lb)\b"#, line) { row.addedLoad = load.1[0]; row.unit = load.1[1].lowercased() }
                if let pace = first(#"(?i)(\d+):(\d{2})\s*(?:min)?/(km|mi)"#, line), let minutes = Double(pace.1[0]), let seconds = Double(pace.1[1]), seconds < 60, minutes * 60 + seconds > 0 {
                    row.speed = String(3600 / (minutes * 60 + seconds)); row.distanceUnit = pace.1[2].lowercased() == "mi" ? .mi : .km
                }
                draft.exercises.append(row); continue
            }
            let pattern = #"(?i)(\d+)\s*(?:x|×|sets?\s*(?:of)?)\s*(\d+)(?!\d)(?:\s*reps?)?"#
            if let match = first(pattern, line) {
                row.kind = .strength; row.sets = match.1[0]; row.reps = match.1[1]
                row.name = String(line[..<match.0.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " -–—:•\t"))
                if line.range(of: #"\d\s*[-–]\s*\d"#, options: .regularExpression) != nil {
                    row.reps = ""; draft.notes.append(L10n.s("A range in “\(row.name)” needs a single confirmed target."))
                }
            } else { row.name = line }
            if let load = first(#"(?i)(?<![-\d.,])(\d+(?:[.,]\d+)?)\s*(kg|lb)\b"#, line) {
                row.weight = load.1[0]; row.unit = load.1[1].lowercased()
            }
            if let rest = first(#"(?i)(?:rest|descanso)\s*[:=]?\s*(\d+)\s*(s|sec(?:onds?)?|min(?:utes?)?)\b"#, line), let n = Int(rest.1[0]) {
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
        guard draft.exercises.count <= 50 else { throw WorkoutError.invalidInput(L10n.s("Import at most 50 exercise lines.")) }
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
