import Foundation

public enum LoadConvention: String, Codable, CaseIterable, Sendable {
    case total, perDumbbell, machineStack, assistance, bodyweight
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let convention = Self(rawValue: value) else {
            throw WorkoutError.invalidInput(L10n.s("Unsupported loadConvention. Use total, perDumbbell, machineStack, assistance or bodyweight."))
        }
        self = convention
    }
    public var label: String {
        switch self {
        case .total: return L10n.s("total external load")
        case .perDumbbell: return L10n.s("per dumbbell")
        case .machineStack: return L10n.s("machine stack setting")
        case .assistance: return L10n.s("assistance setting (more means more assistance)")
        case .bodyweight: return L10n.s("bodyweight; external load not recorded")
        }
    }
}

/// A closed vocabulary, never a script, sensor command, or model instruction.
public enum ObservationKind: String, Codable, Sendable {
    case performance, loggingInterval, effort
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let kind = Self(rawValue: text) else {
            throw WorkoutError.invalidInput(L10n.s("Unsupported observation. Use performance, loggingInterval, or effort. Actual rest, technique, motion and medical assessments are not collected. Ask your coach to revise the request."))
        }
        self = kind
    }
}

public struct ObservationRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: ObservationKind
    public let exerciseID: UUID
    public let afterSet: Int?
    public init(id: String, kind: ObservationKind, exerciseID: UUID, afterSet: Int? = nil) {
        self.id = id; self.kind = kind; self.exerciseID = exerciseID; self.afterSet = afterSet
    }
    private enum CodingKeys: String, CodingKey { case id, kind, exerciseID, afterSet }
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: AnyKey.self)
        guard all.allKeys.allSatisfy({ CodingKeys(rawValue: $0.stringValue) != nil }) else {
            throw WorkoutError.invalidInput(L10n.s("Unsupported observation option. Requests only accept id, kind, exerciseID, and afterSet for effort. No custom instructions or capture commands are supported."))
        }
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        kind = try fields.decode(ObservationKind.self, forKey: .kind)
        exerciseID = try fields.decode(UUID.self, forKey: .exerciseID)
        afterSet = try fields.decodeIfPresent(Int.self, forKey: .afterSet)
    }
    public func collectionDescription(in plan: WorkoutPlan) -> String {
        let name = plan.exercises.first { $0.id == exerciseID }?.name ?? "Exercise"
        switch kind {
        case .performance: return L10n.s("\(name): compare each logged load and repetition count with its prescribed target. Values are confirmed by tapping Log set.")
        case .loggingInterval: return L10n.s("\(name): record Log-tap timestamps and intervals between consecutive sets. Intervals include exercise time; actual rest and set duration are unavailable.")
        case .effort: return L10n.s("\(name), after set \(afterSet ?? 0): one optional effort rating, 1 (easy) to 10 (maximal). You can skip it. No sensor inference.")
        }
    }
}

public struct EffortResponse: Codable, Equatable, Sendable {
    public let requestID: String
    public let setID: UUID
    /// nil records an explicit skip or continuing without answering; never a default rating.
    public let rating: Int?
    public let recordedAt: Date
}

public struct ObservationEvidence: Equatable, Identifiable, Sendable {
    public let id: String
    public let requestID: String
    public let exerciseID: UUID
    public let setNumber: Int
    public let setID: UUID?
    public let title: String
    public let detail: String
}

extension WorkoutPlan {
    public var observationRequests: [ObservationRequest] { observations ?? [] }
    public func validateObservations() throws {
        guard observationSchemaVersion == nil || observationSchemaVersion == 1 else {
            throw WorkoutError.invalidPlan(L10n.s("Unsupported observation schema version. This app supports version 1."))
        }
        let requests = observationRequests
        guard requests.count <= 12, requests.isEmpty || totalSets <= 100 else {
            throw WorkoutError.invalidPlan(L10n.s("Use at most 12 observation requests and at most 100 sets when collecting observations."))
        }
        guard Set(requests.map(\.id)).count == requests.count,
              Set(requests.map { "\($0.exerciseID)-\($0.kind.rawValue)" }).count == requests.count,
              requests.filter({ $0.kind == .effort }).count <= 1 else {
            throw WorkoutError.invalidPlan(L10n.s("Observation IDs must be unique. Use each kind once per exercise, and only one optional effort question per workout."))
        }
        for request in requests {
            guard Self.validIdentifier(request.id), let exercise = exercises.first(where: { $0.id == request.exerciseID }) else {
                throw WorkoutError.invalidPlan(L10n.s("Each observation needs a unique 1–64 character ID (letters, digits, hyphens or underscores) and an exerciseID matching an exercise’s explicit UUID id."))
            }
            guard exercise.kind == .strength else { throw WorkoutError.invalidPlan(L10n.s("Set observations require a strength exercise. Timed activities already report their explicit timing and optional machine values.")) }
            if request.kind == .effort {
                guard exercise.kind == .strength, request.afterSet == exercise.sets else {
                    throw WorkoutError.invalidPlan(L10n.s("An effort question must specify afterSet equal to that exercise’s final prescribed set."))
                }
            } else if request.afterSet != nil {
                throw WorkoutError.invalidPlan(L10n.s("Only effort supports afterSet. Performance and loggingInterval cover all sets of the selected exercise."))
            }
        }
    }
    public static func validIdentifier(_ value: String) -> Bool {
        (1...64).contains(value.utf8.count) && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
}

extension ExercisePlan {
    /// Missing metadata never licenses a name-only comparison. IDs denote the exact
    /// equipment/variation; a renamed display label does not change that identity.
    public func matches(_ other: ExercisePlan, unit: WeightUnit, otherUnit: WeightUnit) -> Bool {
        guard let comparisonID, let loadConvention, other.comparisonID == comparisonID,
              other.loadConvention == loadConvention, unit == otherUnit else { return false }
        return true
    }
}

extension WorkoutSession {
    public var pendingEffort: ObservationRequest? {
        guard effortResponse == nil else { return nil }
        return plan.observationRequests.first { request in
            request.kind == .effort && entries.contains { $0.exerciseID == request.exerciseID && $0.setNumber == request.afterSet }
        }
    }
    public var isReadyForDelivery: Bool { phase == .completed && pendingEffort == nil }

    public var observationEvidence: [ObservationEvidence] {
        plan.observationRequests.flatMap { request -> [ObservationEvidence] in
            guard let exercise = plan.exercises.first(where: { $0.id == request.exerciseID }) else { return [] }
            let numbers = request.kind == .effort ? [request.afterSet ?? exercise.sets] : Array(1...exercise.sets)
            return numbers.map { number in
                let entry = entries.first { $0.exerciseID == exercise.id && $0.setNumber == number }
                let detail: String
                switch request.kind {
                case .performance:
                    let target = exercise.loadIsUnspecified == true ? L10n.s("Prescribed: \(exercise.reps) reps. Load not prescribed.") : L10n.s("Prescribed: \(Self.number(exercise.weight)) \(plan.unit.rawValue) × \(exercise.reps) reps.")
                    if let entry, exercise.loadIsUnspecified == true {
                        detail = L10n.s("\(target)\nUser-confirmed: \(Self.number(entry.weight)) \(plan.unit.rawValue) × \(entry.reps) reps. Load difference unavailable: no prescribed load.")
                    } else if let entry {
                        detail = L10n.s("\(target)\nUser-confirmed: \(Self.number(entry.weight)) \(plan.unit.rawValue) × \(entry.reps) reps. Difference: \(Self.number(entry.weight - exercise.weight)) \(plan.unit.rawValue), \(entry.reps - exercise.reps) reps.")
                    } else { detail = L10n.s("\(target)\nUnavailable: set not logged; no actual values inferred.") }
                case .loggingInterval:
                    if let entry {
                        let event = L10n.s("Measured event: Log tapped at \(ISO8601DateFormatter().string(from: entry.completedAt)).")
                        let interval = loggingInterval(before: entry).map { L10n.s("Log-tap interval: \(Self.number($0)) s. Includes exercise time; not actual rest.") }
                            ?? L10n.s("Log-tap interval unavailable: needs consecutive sets with consistent clocks from this recording version.")
                        detail = L10n.s("\(event)\n\(interval)\nPrescribed rest: \(exercise.restSeconds) s. Actual rest, set start/end and repetition timing are unavailable.")
                    } else { detail = L10n.s("Unavailable: set not logged. Prescribed rest: \(exercise.restSeconds) s; no measured rest inferred.") }
                case .effort:
                    if let response = effortResponse, response.requestID == request.id, response.setID == entry?.id {
                        detail = response.rating.map { L10n.s("User-confirmed effort: \($0)/10 (1 easy · 10 maximal). Subjective rating for this set.") }
                            ?? L10n.s("Skipped: no effort rating supplied.")
                    } else { detail = entry == nil ? L10n.s("Unavailable: the requested final set was not logged.") : L10n.s("Not answered yet. Optional; no effort value inferred.") }
                }
                return ObservationEvidence(id: "\(request.id)-\(number)", requestID: request.id, exerciseID: exercise.id,
                    setNumber: number, setID: entry?.id, title: L10n.s("\(exercise.name) · Set \(number)"), detail: detail)
            }
        }
    }

    /// Uptime checks reject wall-clock changes and likely reboots. Legacy sets have
    /// no uptime and are deliberately unavailable, even though they have a Date.
    public func loggingInterval(before entry: CompletedSet) -> TimeInterval? {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }), index > 0,
              let current = entry.loggedUptime, let previous = entries[index - 1].loggedUptime else { return nil }
        let prior = entries[index - 1]
        let interval = current - previous
        let wall = entry.completedAt.timeIntervalSince(prior.completedAt)
        guard prior.exerciseID == entry.exerciseID, prior.setNumber + 1 == entry.setNumber,
              interval.isFinite, interval >= 0, interval <= 21_600, abs(interval - wall) <= 2 else { return nil }
        return interval
    }

    public func validateEffort() throws {
        guard let response = effortResponse else { return }
        guard let request = plan.observationRequests.first(where: { $0.id == response.requestID && $0.kind == .effort }),
              let entry = entries.first(where: { $0.id == response.setID }),
              entry.exerciseID == request.exerciseID, entry.setNumber == request.afterSet,
              response.rating.map({ (1...10).contains($0) }) ?? true,
              response.recordedAt.timeIntervalSince1970.isFinite, response.recordedAt >= entry.completedAt else {
            throw WorkoutError.invalidInput(L10n.s("The received effort observation has an invalid rating or set reference."))
        }
    }
}
