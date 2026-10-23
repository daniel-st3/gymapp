import Foundation

/// Groups explicit exercise blocks from ordinary coach messages. This is text
/// structure recognition, not exercise generation. Quantities still go through
/// the same bounded parser; the complete source remains available in preview.
enum ConversationalWorkoutImport {
    static func normalized(_ text: String) -> String? {
        // Normalize explicit notation, not quantities. Chat screenshots commonly
        // wrap a numbered name and show "3 series x 10" on the next line.
        let notation = text.replacingOccurrences(of: #"(?i)(\d+)\s+(?:series|sets)\s*[x×]\s*"#, with: "$1 x ", options: .regularExpression)
        let raw = notation.components(separatedBy: .newlines)
        guard notation != text || raw.contains(where: { $0.contains("**") || matches(#"^\s*(?:\d+[.)]|#{1,4}\s|[-•]\s)|(?i:series|sets|repeticiones|repetitions)\s*:"#, $0) }) ||
                raw.contains(where: { matches(#"^\s*\d+\s*(?:x|×|series\s+de|sets\s+of)\s*\d"#, $0) }) else { return nil }
        var title = "", pending = "", records: [String] = []
        var active: String?, sets: String?, reps: String?
        var activeHasQuantity = false
        var details: [String] = []
        func finish() {
            if var value = active {
                if let sets, let reps { value += " \(sets) x \(reps)" }
                else if sets != nil || reps != nil {
                    // Keep partial labelled blocks visibly unresolved.
                    details.append(sets.map { "Series: \($0)" } ?? "Reps: \(reps!)")
                }
                records.append(([value] + details).joined(separator: " · "))
            }
            active = nil; sets = nil; reps = nil; details = []; activeHasQuantity = false
        }
        for original in raw {
            let numbered = matches(#"^\s*\d+[.)]\s+"#, original)
            let heading = matches(#"^\s*#{1,4}\s+"#, original)
            let line = original.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: #"^\s*(?:\d+[.)]\s+|#{1,4}\s+|[-•]\s+)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, line != "---", !SmartWorkoutImport.isDateMetadata(line) else { continue }
            if ["chatgpt", "message chatgpt", "pregunta lo que quieras", "ask anything", "envía un mensaje"].contains(line.lowercased()) { continue }
            if matches(#"(?i)^(?:workout|title|entrenamiento|rutina)\s*:"#, line) {
                title = String(line.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces); continue
            }
            if let quantity = capture(#"(?i)^(?:series|sets)\s*:\s*(\d+(?:\s*[-–]\s*\d+)?)\s*$"#, line) {
                if active == nil, !pending.isEmpty { active = pending; pending = "" }
                sets = quantity; continue
            }
            if let quantity = capture(#"(?i)^(?:reps|repeticiones|repetitions)\s*:\s*(\d+(?:\s*[-–]\s*\d+)?)\s*$"#, line) {
                if active == nil, !pending.isEmpty { active = pending; pending = "" }
                reps = quantity; continue
            }
            if let range = line.range(of: #"(?i)\d+(?:\s*[-–]\s*\d+)?\s*(?:x|×|series\s*(?:de)?|sets\s*(?:of)?)\s*\d"#, options: .regularExpression) {
                let name = line[..<range.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: " :—–-·"))
                if name.isEmpty, active != nil, !activeHasQuantity, sets == nil, reps == nil {
                    active! += " " + line; activeHasQuantity = true
                } else if !name.isEmpty || !pending.isEmpty {
                    finish(); active = name.isEmpty ? pending + " " + line : line; pending = ""; activeHasQuantity = true
                }
                continue
            }
            if matches(#"(?i)^(?:rest|descanso|peso|carga|load|weight)\s*[:=]?\s*\d"#, line), active != nil {
                details.append(line); continue
            }
            if matches(#"(?i)\b(?:caminadora|caminar|walking|treadmill|running|correr|movilidad|mobility)\b.*\d+\s*(?:min|minutes|minutos)\b"#, line) {
                finish(); records.append(line); pending = ""; continue
            }
            if numbered {
                finish(); active = line; pending = ""; continue
            }
            if heading {
                finish()
                if heading && title.isEmpty && records.isEmpty { title = line }
                pending = line; continue
            }
            // Short unnumbered names can precede quantity lines (Vision often
            // loses bullets). Prose stays in source, never becomes fake work.
            if !line.contains(where: \.isNumber), line.count <= 80, !line.hasSuffix("."), !line.hasSuffix("?") {
                if active != nil, !activeHasQuantity, sets == nil, reps == nil, details.isEmpty {
                    active! += " " + line; continue
                }
                if title.isEmpty && records.isEmpty && active == nil { title = line }
                pending = line
            }
        }
        finish()
        guard !records.isEmpty else { return nil }
        // Without a title marker the ordinary parser could mistake the first
        // incomplete exercise for the workout's name and hide it from review.
        return "Workout: " + (title.isEmpty ? L10n.s("My workout") : title) + "\n" + records.joined(separator: "\n")
    }
    private static func matches(_ pattern: String, _ value: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    private static func capture(_ pattern: String, _ value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }
}

extension WorkoutDraft {
    /// Explicit user action from preview. Prescribed values are never replaced.
    public mutating func fillMissingRest(_ seconds: Int) throws {
        guard (0...1800).contains(seconds) else { throw WorkoutError.invalidInput(L10n.s("Choose rest from 0 to 1800 seconds.")) }
        for i in exercises.indices where exercises[i].kind == .strength && exercises[i].rest.isEmpty { exercises[i].rest = String(seconds) }
    }
    public mutating func fillMissingUnit(_ unit: WeightUnit) {
        for i in exercises.indices where exercises[i].kind == .strength && exercises[i].unit.isEmpty { exercises[i].unit = unit.rawValue }
    }
}

extension DraftExercise {
    public var repetitionChoices: [Int] {
        let pattern = #"(?i)(?:\d+\s*(?:x|×|series\s*(?:de)?|sets\s*(?:of)?)\s*|(?:reps|repeticiones)\s*:\s*)(\d+)\s*[-–]\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let a = Range(match.range(at: 1), in: source), let b = Range(match.range(at: 2), in: source),
              let lower = Int(source[a]), let upper = Int(source[b]), (1...200).contains(lower), (lower...200).contains(upper) else { return [] }
        return Array(Set([lower, upper])).sorted()
    }
}

extension WatchState {
    public var canReplaceUnloggedWorkout: Bool {
        guard let session, let plan else { return false }
        return session.plan != plan && session.phase == .active && session.entries.isEmpty && (session.activities ?? []).isEmpty && session.activityTimer == nil
    }
    /// Explicit Watch acceptance only. An active workout with any recorded work
    /// is never discarded, even if a newer plan is already waiting on the phone.
    public mutating func replaceUnloggedWorkout(now: Date = Date()) throws {
        guard canReplaceUnloggedWorkout, let plan else { throw WorkoutError.invalidState(L10n.s("Recorded work stays with its original workout.")) }
        session = try WorkoutSession(plan: plan, now: now)
    }
}
