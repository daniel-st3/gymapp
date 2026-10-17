import Foundation

public struct ExerciseHelp: Identifiable, Sendable {
    public let id: String
    public let english: String
    public let spanish: String
    public let aliases: [String]
    public let equipment: String
    public let explanation: String
    public var displayName: String { L10n.language == "es" ? spanish : english }
    public var translatedName: String { L10n.language == "es" ? english : spanish }
}
public enum ExerciseCatalog {
    /// Original short descriptions; no copied media, injury advice, automatic
    /// machine identification or assertion of availability at a specific gym.
    public static var items: [ExerciseHelp] { [
        .init(id: "seated-leg-curl", english: "Seated leg curl", spanish: "Curl femoral sentado", aliases: ["curl de pierna sentado", "flexión de rodilla sentado"], equipment: L10n.s("Seated leg-curl machine"), explanation: L10n.s("Sit with your back against the pad. Bend your knees to bring the lower roller down; return with control. Follow the machine’s adjustment guide.")),
        .init(id: "lying-leg-curl", english: "Lying leg curl", spanish: "Curl femoral tumbado", aliases: ["curl femoral acostado", "prone leg curl"], equipment: L10n.s("Lying leg-curl machine"), explanation: L10n.s("Lie on the machine with the roller behind your lower legs. Bend your knees and return with control. This is a different variation from the seated machine.")),
        .init(id: "seated-row", english: "Seated row", spanish: "Remo sentado", aliases: ["remo en máquina", "cable row"], equipment: L10n.s("Row machine or cable station; confirm which"), explanation: L10n.s("Sit facing the handles. Pull toward your torso and return with control. Record the exact machine and grip separately.")),
        .init(id: "chest-press", english: "Chest press", spanish: "Press de pecho", aliases: ["press de pecho en máquina", "machine chest press"], equipment: L10n.s("Chest-press machine"), explanation: L10n.s("Adjust the seat using the machine’s guide. Push the handles away and return with control. Different machines use different load conventions.")),
        .init(id: "lat-pulldown", english: "Lat pulldown", spanish: "Jalón al pecho", aliases: ["jalon al pecho", "pulldown"], equipment: L10n.s("High cable station"), explanation: L10n.s("Sit beneath the bar with the thigh pad adjusted. Pull toward the upper chest and return with control. Keep the chosen handle and grip in the variation name.")),
        .init(id: "dumbbell-curl", english: "Dumbbell curl", spanish: "Curl con mancuernas", aliases: ["curl de biceps", "biceps curl"], equipment: L10n.s("Dumbbells"), explanation: L10n.s("Bend your elbows to raise the dumbbells, then lower with control. State whether the recorded load is per dumbbell or total.")),
        .init(id: "treadmill-walk", english: "Treadmill walk", spanish: "Caminata en caminadora", aliases: ["caminar", "walking", "cinta de caminar"], equipment: L10n.s("Treadmill"), explanation: L10n.s("Start the activity timer when you begin walking. Pause when you stop; enter machine distance, speed or incline only if you have those readings. Indoor GPS does not measure treadmill distance.")),
        .init(id: "mobility", english: "Mobility", spanish: "Movilidad", aliases: ["movilidad articular"], equipment: L10n.s("As prescribed by your coach"), explanation: L10n.s("Use the timed activity for your prescribed movement. The timer records elapsed time; it does not judge range of motion or technique."))
    ] }
    private static func normalized(_ value: String) -> String { value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).trimmingCharacters(in: .whitespacesAndNewlines) }
    public static func search(_ query: String) -> [ExerciseHelp] {
        let q = normalized(query)
        return items.filter { q.isEmpty || ([$0.english, $0.spanish] + $0.aliases).contains { normalized($0).contains(q) } }
    }
}

public struct SavedExerciseReference: Identifiable, Sendable {
    public let plan: WorkoutPlan
    public let exercise: ExercisePlan
    public var id: String { "\(plan.id)-\(exercise.id)" }
}
extension PhoneState {
    /// Search the user's actual prescriptions without inferring gym inventory or
    /// merging similarly named machines. No history or private profile is sent.
    public func savedExercises(matching query: String) -> [SavedExerciseReference] {
        let query = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        return ([plan].compactMap { $0 } + routineLibrary.map(\.plan)).flatMap { plan in
            plan.exercises.compactMap { exercise in
                let reference = SavedExerciseReference(plan: plan, exercise: exercise)
                let text = (exercise.name + " " + plan.title).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                guard (query.isEmpty || text.contains(query)), seen.insert(reference.id).inserted else { return nil }
                return reference
            }
        }
    }
}
