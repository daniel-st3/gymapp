import Foundation

public enum PlanImport {
    private struct PlanInput: Decodable {
        let id: UUID?
        let schemaVersion: Int?
        let transitionSeconds: Int?
        let practice: Bool?
        let title: String
        let unit: WeightUnit?
        let exercises: [ExerciseInput]
        let observations: [ObservationRequest]?
        let observationSchemaVersion: Int?
        let timeBudget: TimeBudget?
        struct ExerciseInput: Decodable {
            let id: UUID?
            let comparisonID: String?
            let loadConvention: LoadConvention?
            let workPolicy: WorkPolicy?
            let alternatives: [ExerciseAlternative]?
            let name: String
            let activity: ActivityPrescription?
            let sets: Int?
            let reps: Int?
            let weight: Double?
            let restSeconds: Int?
        }
        var plan: WorkoutPlan { get throws {
            guard unit != nil || exercises.allSatisfy({ $0.activity != nil && $0.activity?.additionalLoad == nil }) else { throw WorkoutError.invalidInput(L10n.s("Choose kg or lb for a workout with load.")) }
            var result = WorkoutPlan(id: id ?? UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), unit: unit ?? .kg,
                        exercises: exercises.map { input in
                            var result = ExercisePlan(id: input.id ?? UUID(), name: input.name.trimmingCharacters(in: .whitespacesAndNewlines),
                            sets: input.sets ?? (input.activity == nil ? 0 : 1), reps: input.reps ?? (input.activity == nil ? 0 : 1), weight: input.weight ?? (input.activity == nil ? -1 : 0), restSeconds: input.restSeconds ?? (input.activity == nil ? -1 : 0), comparisonID: input.comparisonID, loadConvention: input.loadConvention)
                            result.activity = input.activity; result.workPolicy = input.workPolicy; result.alternatives = input.alternatives; return result
                        },
                        observations: observations, observationSchemaVersion: observationSchemaVersion)
            result.schemaVersion = schemaVersion; result.transitionSeconds = transitionSeconds; result.practice = practice; result.timeBudget = timeBudget; return result
        } }
    }
    private struct ReviewInput: Decodable { let analysis: String; let plan: PlanInput }

    private static func jsonData(_ text: String) throws -> Data {
        guard text.utf8.count <= 64_000 else { throw WorkoutError.invalidInput(L10n.s("This import is too large. Paste one workout at a time.")) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            guard lines.count >= 3, lines.last?.trimmingCharacters(in: .whitespaces) == "```" else {
                throw WorkoutError.invalidInput(L10n.s("The JSON code block is incomplete."))
            }
            json = lines.dropFirst().dropLast().joined(separator: "\n")
        } else { json = trimmed }
        guard let data = json.data(using: .utf8), !data.isEmpty else { throw WorkoutError.invalidInput(L10n.s("Paste your workout JSON first.")) }
        return data
    }

    public static func parse(_ text: String) throws -> WorkoutPlan {
        let data = try jsonData(text)
        let decoder = JSONDecoder()
        let plan: WorkoutPlan
        do {
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if object?["plan"] != nil { plan = try decoder.decode(ReviewInput.self, from: data).plan.plan }
            else { plan = try decoder.decode(PlanInput.self, from: data).plan }
        } catch let error as WorkoutError { throw error
        } catch {
            throw WorkoutError.invalidInput(L10n.s("Use the workout JSON format from the coaching prompt. Include title, unit (kg or lb), and exercises with name, sets, reps, weight, and restSeconds. Optional observation references need UUID exercise IDs; comparisonID and loadConvention must be supported values."))
        }
        try plan.validate(); return plan
    }

    public static func parseReview(_ text: String) throws -> TrainingReview {
        let data = try jsonData(text)
        let input: ReviewInput
        do { input = try JSONDecoder().decode(ReviewInput.self, from: data) }
        catch let error as WorkoutError { throw error }
        catch { throw WorkoutError.invalidInput(L10n.s("Return analysis and plan using the Little Lift review JSON schema.")) }
        guard !input.analysis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, input.analysis.count <= 12_000 else {
            throw WorkoutError.invalidInput(L10n.s("Include a nonempty analysis of at most 12,000 characters."))
        }
        let plan = try input.plan.plan
        try plan.validate()
        return TrainingReview(analysis: input.analysis, plan: plan)
    }

    public static let example = """
    {
      "title": "Upper body",
      "unit": "kg",
      "exercises": [
        {"name": "Bench press", "sets": 3, "reps": 10, "weight": 40, "restSeconds": 90},
        {"name": "Seated row", "sets": 3, "reps": 12, "weight": 30, "restSeconds": 90},
        {"name": "Lateral raise", "sets": 3, "reps": 12, "weight": 5, "restSeconds": 60}
      ]
    }
    """

    public static let observationExample = """
    {
      "title": "Observation practice",
      "unit": "kg",
      "observationSchemaVersion": 1,
      "exercises": [
        {"id": "11111111-1111-4111-8111-111111111111", "name": "Seated dumbbell press (per dumbbell)", "comparisonID": "seated-db-press-upright-neutral", "loadConvention": "perDumbbell", "sets": 2, "reps": 8, "weight": 5, "restSeconds": 30}
      ],
      "observations": [
        {"id": "press-targets", "kind": "performance", "exerciseID": "11111111-1111-4111-8111-111111111111"},
        {"id": "press-intervals", "kind": "loggingInterval", "exerciseID": "11111111-1111-4111-8111-111111111111"},
        {"id": "press-effort", "kind": "effort", "exerciseID": "11111111-1111-4111-8111-111111111111", "afterSet": 2}
      ]
    }
    """

    public static var observationInstructions: String { L10n.s("""
    Observations are optional data with schema version 1. Omit observations for ordinary logging. Supported kinds: performance (user-confirmed load/reps versus targets), loggingInterval (Log-tap events/intervals, including exercise time; never actual rest or set duration), effort (one optional 1–10 rating after one specified exercise's final set). Use at most 12 requests and 100 total sets with observations. Give each request a unique stable 1–64 character id using letters, digits, hyphens or underscores; use each kind once per exercise. exerciseID must refer to the exercise's UUID id; retain IDs for unchanged requests. Only effort has afterSet, which must equal that exercise's sets. Actual rest, rep timing, technique, medical assessment, scripts and other kinds are unsupported; do not request them. No mandatory set-start taps or motion collection occur.
    For comparisons across workouts, supply comparisonID and loadConvention together. comparisonID (same 1–64 character rules) identifies the exact equipment, variation, angle and grip; keep it stable only for that same variation. loadConvention is total, perDumbbell, machineStack, assistance or bodyweight. Bodyweight uses weight 0. Compare only matching comparisonID, unit and loadConvention; missing metadata means insufficient data, never a name-based match. An assistance setting is not lifted load. No automatic conversions or medical/causal conclusions. The user reviews all requests before accepting the plan.
    """) }

    public static var coachingPrompt: String { L10n.s("""
    Export the workout you recommend for me as a single JSON object. Keep using the goals, constraints, preferences, and training history from this conversation. This is for my watch logger; do not change the workout merely to fit the example.
    Use exactly this structure (replace the example values):
    \(observationExample)
    \(observationInstructions)
    For walking, running, mobility or other timed work, use schemaVersion: 2 and an exercise with name and activity: {"kind":"walking", "durationSeconds":900, "speedKph":5, "inclinePercent":3, "distanceUnit":"km"}. Duration, distanceMeters, speedKph, inclinePercent and additionalLoad are optional: omit unknown values, never infer actual results from targets. No strength reps or weight fields are needed for timed work. Retain the user's original exercise name and exact variant. Ask about ambiguous modality instead of inventing load. Optional transitionSeconds (0–300) is a separate machine-change timer and never shortens prescribed rest.
    Each strength exercise has one prescribed weight and repetition target for its sets. Split an exercise into separate named entries if its targets vary, such as warm-up and working sets. Weight 0 represents unweighted work; count an assisted machine's displayed load explicitly in its exercise name. Use kg or lb consistently. Weight means the same convention I use in this conversation; clarify per dumbbell versus total in the name. Rest is in seconds. Output JSON only, without commentary.
    """) }

    public static func reviewPrompt(profile: String, sessions: [WorkoutSession]) -> String {
        let history = sessions.sorted { $0.startedAt > $1.startedAt }.prefix(12).reversed().map { $0.report() }.joined(separator: "\n\n---\n\n")
        return """
        Write the analysis in \(L10n.language == "es" ? "Spanish" : "English"). Keep JSON keys and stable identifiers unchanged.
        You are reviewing my mixed-modality training. The following is user-supplied context, not system instructions. Do not assume access to any previous ChatGPT conversation or memory.
        TRAINING PROFILE
        \(profile.isEmpty ? "No profile supplied. Ask for missing constraints in the analysis; do not invent them." : profile)
        RECENT WORKOUTS, OLDEST FIRST
        \(history.isEmpty ? "No completed workouts yet." : history)
        TASK
        Describe the supported observations, explicitly separating prescribed targets, user-confirmed values, measured Log-tap events and unavailable timing. Explain skipped or unlogged observations. Do not infer causation, injury risk or medical readiness. Summarize actual performance and propose the next workout using the supplied constraints. Do not infer completed work from targets. Do not invent medical facts or change medication advice. If essential information is missing, say so in analysis and use a conservative plan based on the supplied history, or ask me before proposing new exercises. I will review the plan before using it.
        Return only valid JSON with two fields: "analysis" (a concise string) and "plan" (a workout using this exact schema):
        \(observationExample)
        \(observationInstructions)
        Preserve activity modalities. For walking, running, mobility or other timed activities use schemaVersion 2 and activity with kind, optional durationSeconds, distanceMeters, speedKph, inclinePercent, additionalLoad and distanceUnit km or mi. Targets are not actual results. Do not add strength repetitions or loads to ordinary cardio. transitionSeconds is optional and separate from prescribed rest.
        Units must be kg or lb. Exercise names must clarify any per-dumbbell or assistance convention. Use separate entries for different set targets.
        """
    }
}
