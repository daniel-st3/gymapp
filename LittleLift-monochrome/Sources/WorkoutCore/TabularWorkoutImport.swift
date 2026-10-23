import Foundation

/// Explicit column headings supply meaning. Unlabelled OCR columns never become
/// invented sets, load units or rest. Original source remains in the draft.
enum TabularWorkoutImport {
    static func extract(_ text: String) -> WorkoutDraft? {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var columns: [String] = [], delimiter: Character = "|", headerIndex: Int?
        for (index, line) in lines.enumerated() {
            for separator: Character in ["|", "\t", ";"] {
                let cells = split(line, by: separator)
                let fields = cells.map(field)
                if fields.contains("name"), fields.contains("sets"), fields.contains("reps") {
                    columns = cells; delimiter = separator; headerIndex = index; break
                }
            }
            if headerIndex != nil { break }
        }
        guard let headerIndex else { return nil }
        var draft = WorkoutDraft(); draft.source = text
        draft.title = lines.prefix(headerIndex).first.map { line in
            if let colon = line.firstIndex(of: ":") { return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces) }
            return line.trimmingCharacters(in: CharacterSet(charactersIn: "# *"))
        } ?? ""
        let keys = columns.map(field)
        guard Set(keys.filter { !$0.isEmpty }).count == keys.filter({ !$0.isEmpty }).count else {
            draft.notes = [L10n.s("Duplicate table columns need a manual decision. The source is preserved below.")]
            draft.exercises = [DraftExercise()]; return draft
        }
        for line in lines.dropFirst(headerIndex + 1) {
            if line.allSatisfy({ "|-:;\t ".contains($0) }) { continue }
            var row = DraftExercise(); row.kind = .strength; row.source = line
            let cells = split(line, by: delimiter)
            guard cells.count == columns.count else {
                row.name = line
                draft.exercises.append(row)
                draft.notes.append(L10n.s("A table row does not match its headings. Check the source before filling its fields.")); continue
            }
            for (index, value) in cells.enumerated() {
                switch keys[index] {
                case "name": row.name = value
                case "sets": row.sets = SmartWorkoutImport.cleanExtractedNumber(value, kind: "sets")
                case "reps": row.reps = SmartWorkoutImport.cleanExtractedNumber(value, kind: "reps")
                case "weight":
                    row.weight = SmartWorkoutImport.cleanExtractedNumber(value, kind: "weight")
                    let explicit = unit(value) ?? unit(columns[index]); if let explicit { row.unit = explicit }
                case "unit": break // applied after load so contradictory units cannot be overwritten
                case "rest":
                    let header = columns[index].lowercased()
                    let labelled = SmartWorkoutImport.cleanExtractedNumber(value, kind: "rest")
                    if labelled != value || value.rangeOfCharacter(from: .letters) != nil { row.rest = labelled }
                    else if header.contains("min"), let number = Int(value), (0...30).contains(number) { row.rest = String(number * 60) }
                    else if header.contains("sec") || header.contains("seg") || header.contains("(s)") { row.rest = value }
                case "convention": row.convention = SmartWorkoutImport.explicitConvention(in: value)
                case "variation": row.comparisonID = value
                default: break
                }
            }
            if let index = keys.firstIndex(of: "unit") {
                let explicit = unit(cells[index])
                row.unit = (row.unit.isEmpty || row.unit == explicit) ? (explicit ?? "") : ""
            }
            draft.exercises.append(row)
        }
        draft.notes.insert(L10n.s("Table headings were used. Empty or conflicting fields need confirmation; no missing values were assumed."), at: 0)
        if draft.exercises.isEmpty { draft.exercises = [DraftExercise()] }
        return draft
    }
    private static func split(_ line: String, by separator: Character) -> [String] {
        var cells = line.split(separator: separator, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if separator == "|" { if cells.first == "" { cells.removeFirst() }; if cells.last == "" { cells.removeLast() } }
        return cells
    }
    private static func unit(_ value: String) -> String? {
        let lower = value.lowercased()
        let kg = lower.range(of: #"\bkg\b"#, options: .regularExpression) != nil
        let lb = lower.range(of: #"\blbs?\b"#, options: .regularExpression) != nil
        return kg == lb ? nil : (kg ? "kg" : "lb")
    }
    private static func field(_ value: String) -> String {
        let value = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: CharacterSet(charactersIn: " *"))
        if ["exercise", "exercises", "ejercicio", "name", "nombre"].contains(value) { return "name" }
        if ["sets", "set", "series"].contains(value) { return "sets" }
        if ["reps", "repetitions", "repeticiones"].contains(value) { return "reps" }
        if value.hasPrefix("load") || value.hasPrefix("weight") || value.hasPrefix("peso") || value.hasPrefix("carga") || ["kg", "lb", "lbs"].contains(value) { return "weight" }
        if ["unit", "units", "unidad", "unidades"].contains(value) { return "unit" }
        if value.hasPrefix("rest") || value.hasPrefix("descanso") { return "rest" }
        if ["convention", "convencion"].contains(value) { return "convention" }
        if ["variation", "variation id", "variante", "comparisonid"].contains(value) { return "variation" }
        return ""
    }
}

extension DraftExercise {
    public var fieldsToReview: [String] {
        var fields: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.utf8.count > 120 || name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { fields.append(L10n.s("Exercise name")) }
        guard kind == .strength || (kind == nil && !sets.isEmpty && !reps.isEmpty) else {
            if kind == nil { fields.append(L10n.s("Activity type")) }
            else {
                if (try? exercise()) == nil { fields.append(L10n.s("Activity targets")) }
                if !addedLoad.isEmpty && WeightUnit(rawValue: unit) == nil { fields.append(L10n.s("Unit")) }
            }
            return fields
        }
        if Int(sets).map({ (1...20).contains($0) }) != true { fields.append(L10n.s("Sets")) }
        if Int(reps).map({ (1...200).contains($0) }) != true { fields.append(L10n.s("Repetitions")) }
        if !chooseLoadOnWatch, Double(weight.replacingOccurrences(of: ",", with: ".")).map({ $0.isFinite && (0...1000).contains($0) }) != true { fields.append(L10n.s("Load")) }
        if WeightUnit(rawValue: unit) == nil { fields.append(L10n.s("Unit")) }
        if Int(rest).map({ (0...1800).contains($0) }) != true { fields.append(L10n.s("Rest · seconds")) }
        if convention == "bodyweight" && (chooseLoadOnWatch || Double(weight) != 0) { fields.append(L10n.s("Bodyweight must use zero external load")) }
        if (!comparisonID.isEmpty && convention.isEmpty) || (!comparisonID.isEmpty && !WorkoutPlan.validIdentifier(comparisonID)) || (!convention.isEmpty && LoadConvention(rawValue: convention) == nil) { fields.append(L10n.s("Load convention")) }
        return fields
    }
}
