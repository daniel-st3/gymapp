import Foundation

/// Presentation wrappers are not the data format. Never execute copied content.
public enum WorkoutPaste {
    public static func content(_ text: String) throws -> String {
        guard text.utf8.count <= 64_000 else { throw WorkoutError.invalidInput(L10n.s("Import at most 64 KB at a time.")) }
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        let fences = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("```") }
        guard !fences.isEmpty else { return lines.joined(separator: "\n") }
        guard fences.count == 2, let first = fences.first, let last = fences.last, first < last,
              lines[last].trimmingCharacters(in: .whitespaces) == "```" else {
            throw WorkoutError.invalidInput(L10n.s("Copy one complete workout block. This message has incomplete or multiple code blocks."))
        }
        return lines[(first + 1)..<last].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Ordinary incomplete JSON can be edited just like text/OCR. Advanced contracts
/// stay on the strict path so observations or correlation cannot be discarded.
public enum EditableWorkoutJSON {
    public static func extract(_ text: String) throws -> WorkoutDraft {
        let data = try PlanImport.jsonData(text)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WorkoutError.invalidInput(L10n.s("Paste one workout with a title and an exercises list."))
        }
        if ["handoffID", "reviewSessionID", "reviewAttemptID", "connectionCheckID"].contains(where: { object[$0] != nil }) {
            return WorkoutDraft(plan: try PlanImport.parse(text)) // strict correlation rejection
        }
        do {
            var draft = WorkoutDraft(plan: try PlanImport.parse(text)); draft.source = text
            return draft
        } catch {
            // A partial basic prescription may be repaired; unsupported metadata
            // must retain its original validation error, never be silently lost.
            let plan = object["plan"] as? [String: Any] ?? object
            let envelopeKeys = Set(object.keys)
            if object["plan"] != nil && !envelopeKeys.isSubset(of: ["analysis", "plan"]) { throw error }
            let keys: Set<String> = ["id", "schemaVersion", "title", "unit", "exercises"]
            guard Set(plan.keys).isSubset(of: keys),
                  let rows = plan["exercises"] as? [[String: Any]], !rows.isEmpty, rows.count <= 50 else { throw error }
            if let version = plan["schemaVersion"], scalar(version) != "1" && scalar(version) != "2" && scalar(version) != "3" { throw error }
            if let id = plan["id"], UUID(uuidString: scalar(id)) == nil { throw error }
            var draft = WorkoutDraft(); draft.source = text
            draft.title = scalar(plan["title"])
            let allowed: Set<String> = ["id", "name", "sets", "reps", "weight", "restSeconds", "loadIsUnspecified", "loadConvention", "comparisonID"]
            for value in rows {
                guard Set(value.keys).isSubset(of: allowed),
                      value["name"] is String,
                      value.values.allSatisfy({ $0 is String || $0 is NSNumber || $0 is NSNull }) else { throw error }
                var row = DraftExercise(); row.kind = .strength
                if let id = value["id"] {
                    guard let uuid = UUID(uuidString: scalar(id)) else { throw error }
                    row.id = uuid
                }
                row.name = scalar(value["name"])
                row.sets = SmartWorkoutImport.cleanExtractedNumber(scalar(value["sets"]), kind: "sets")
                row.reps = SmartWorkoutImport.cleanExtractedNumber(scalar(value["reps"]), kind: "reps")
                row.rest = SmartWorkoutImport.cleanExtractedNumber(scalar(value["restSeconds"]), kind: "rest")
                row.weight = SmartWorkoutImport.cleanExtractedNumber(scalar(value["weight"]), kind: "weight")
                row.unit = scalar(plan["unit"]).lowercased()
                if row.unit == "lbs" { row.unit = "lb" }
                if let load = SmartWorkoutImport.extractedLoad(scalar(value["weight"])) {
                    row.unit = row.unit.isEmpty || row.unit == load.unit ? load.unit : ""
                }
                row.convention = scalar(value["loadConvention"]); row.comparisonID = scalar(value["comparisonID"])
                if let flag = value["loadIsUnspecified"] {
                    guard scalar(flag) == "true" || scalar(flag) == "false" else { throw error }
                    if scalar(flag) == "true" && !row.weight.isEmpty { throw error }
                }
                row.chooseLoadOnWatch = row.weight.isEmpty
                if row.convention == "bodyweight" { row.chooseLoadOnWatch = false }
                row.source = String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8) ?? ""
                draft.exercises.append(row)
            }
            draft.notes = [L10n.s("Some fields need your confirmation. Original values are kept below; nothing has been saved." )]
            return draft
        }
    }

    private static func scalar(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber {
            if String(cString: number.objCType) == "c" { return number.boolValue ? "true" : "false" }
            return number.stringValue
        }
        return ""
    }
}
