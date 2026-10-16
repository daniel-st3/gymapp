import Foundation

public enum ActivityKind: String, Codable, CaseIterable, Sendable {
    case strength, walking, running, mobility, other
    public var label: String {
        switch self { case .strength: L10n.s("Strength"); case .walking: L10n.s("Walking"); case .running: L10n.s("Running"); case .mobility: L10n.s("Mobility"); case .other: L10n.s("Other timed activity") }
    }
}
public enum DistanceUnit: String, Codable, CaseIterable, Sendable {
    case km, mi
    public var meters: Double { self == .km ? 1000 : 1609.344 }
}
public enum ValueSource: String, Codable, Sendable { case user, machine, watch, estimate; public var label: String { L10n.key(rawValue) } }
public struct ActivityPrescription: Codable, Equatable, Sendable {
    public var kind: ActivityKind
    public var durationSeconds: Double?
    public var distanceMeters: Double?
    public var speedKph: Double?
    public var inclinePercent: Double?
    public var distanceUnit: DistanceUnit
    public var additionalLoad: Double?
    public init(kind: ActivityKind, durationSeconds: Double? = nil, distanceMeters: Double? = nil, speedKph: Double? = nil, inclinePercent: Double? = nil, distanceUnit: DistanceUnit = .km, additionalLoad: Double? = nil) {
        self.kind = kind; self.durationSeconds = durationSeconds; self.distanceMeters = distanceMeters; self.speedKph = speedKph
        self.inclinePercent = inclinePercent; self.distanceUnit = distanceUnit; self.additionalLoad = additionalLoad
    }
    public func validate() throws {
        guard kind != .strength, Self.valid(durationSeconds, 1...21_600), Self.valid(distanceMeters, 1...200_000),
              Self.valid(speedKph, 0.1...80), Self.valid(inclinePercent, -20...50), Self.valid(additionalLoad, 0...200) else {
            throw WorkoutError.invalidInput(L10n.s("Check duration, distance, speed, incline and optional added load. Leave unknown values empty."))
        }
    }
    static func valid(_ value: Double?, _ range: ClosedRange<Double>) -> Bool { value.map { $0.isFinite && range.contains($0) } ?? true }
    public var summary: String {
        var parts: [String] = []
        if let durationSeconds { parts.append(L10n.s("\(WorkoutSession.number(durationSeconds / 60)) min")) }
        if let distanceMeters { parts.append(L10n.s("\(WorkoutSession.number(distanceMeters / distanceUnit.meters)) \(distanceUnit.rawValue)")) }
        if let speedKph { parts.append(L10n.s("\(WorkoutSession.number(speedKph / (distanceUnit == .mi ? 1.609344 : 1))) \(distanceUnit == .mi ? "mph" : "km/h")")) }
        if let inclinePercent { parts.append(L10n.s("\(WorkoutSession.number(inclinePercent)) %")) }
        return parts.isEmpty ? L10n.s("No numeric target") : parts.joined(separator: " · ")
    }
}

public struct ActivitySpan: Codable, Equatable, Sendable {
    public let start: Date
    public var end: Date?
}
/// Explicit taps measure elapsed time between Start/Pause/Resume/Done, not
/// physiological effort. Closed spans exclude pauses and survive relaunch.
public struct ActivityTimer: Codable, Equatable, Sendable {
    public let exerciseID: UUID
    public var spans: [ActivitySpan]
    public var distanceMeters: Double?
    public var speedKph: Double?
    public var inclinePercent: Double?
    public var paused: Bool { spans.last?.end != nil }
    public func elapsed(at date: Date) -> TimeInterval { spans.reduce(0) { $0 + max(0, ($1.end ?? date).timeIntervalSince($1.start)) } }
    public mutating func pause(at date: Date) throws {
        guard InputBoundary.validDate(date), !paused, let last = spans.last, date >= last.start else { throw WorkoutError.invalidState(L10n.s("The activity is already paused or the clock changed.")) }
        spans[spans.count - 1].end = date
    }
    public mutating func resume(at date: Date) throws {
        guard InputBoundary.validDate(date), paused, let end = spans.last?.end, date >= end, spans.count < 200 else { throw WorkoutError.invalidState(L10n.s("The activity cannot resume yet.")) }
        spans.append(ActivitySpan(start: date))
    }
}
public struct ActivityResult: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let exerciseID: UUID
    public let spans: [ActivitySpan]
    public let endedAt: Date
    public var distanceMeters: Double?
    public var speedKph: Double?
    public var inclinePercent: Double?
    public var valuesSource: ValueSource
    public var completed: Bool
    public var elapsedSeconds: Double { spans.reduce(0) { $0 + max(0, ($1.end ?? $1.start).timeIntervalSince($1.start)) } }
    public func validate(start: Date, end: Date) throws {
        guard !spans.isEmpty, spans.count <= 200, InputBoundary.validDate(endedAt), endedAt <= end,
              ActivityPrescription.valid(distanceMeters, 0...200_000), ActivityPrescription.valid(speedKph, 0...80),
              ActivityPrescription.valid(inclinePercent, -20...50) else { throw WorkoutError.invalidInput(L10n.s("Invalid activity result.")) }
        var previous = start
        for span in spans {
            guard let stop = span.end, InputBoundary.validDate(span.start), InputBoundary.validDate(stop),
                  span.start >= previous, stop >= span.start, stop <= endedAt else { throw WorkoutError.invalidInput(L10n.s("Invalid activity timing.")) }
            previous = stop
        }
    }
    public func summary(unit: DistanceUnit) -> String {
        var parts = [L10n.s("\(WorkoutSession.number(elapsedSeconds / 60)) min · Start/Pause/Done events")]
        if let distanceMeters { parts.append(L10n.s("\(WorkoutSession.number(distanceMeters / unit.meters)) \(unit.rawValue) · \(valuesSource.label)")) }
        if let speedKph { parts.append(L10n.s("\(WorkoutSession.number(speedKph / (unit == .mi ? 1.609344 : 1))) \(unit == .mi ? "mph" : "km/h") · \(valuesSource.label)")) }
        if let inclinePercent { parts.append(L10n.s("\(WorkoutSession.number(inclinePercent)) % · \(valuesSource.label)")) }
        if distanceMeters == nil { parts.append(L10n.s("Distance unavailable")) }
        if !completed { parts.append(L10n.s("Stopped early; not completed")) }
        return parts.joined(separator: "\n")
    }
}
extension ExercisePlan {
    public var kind: ActivityKind { activity?.kind ?? .strength }
    public func prescription(unit: WeightUnit) -> String {
        if let activity { return activity.summary + (activity.additionalLoad.map { " · +\(WorkoutSession.number($0)) \(unit.rawValue)" } ?? "") }
        return L10n.s("\(sets) × \(reps) · \(WorkoutSession.number(weight)) \(unit.rawValue) · \(restSeconds)s rest")
    }
}
extension WorkoutSession {
    public func completedCount(for exercise: ExercisePlan) -> Int {
        exercise.kind == .strength ? entries.filter { $0.exerciseID == exercise.id }.count : (activities ?? []).filter { $0.exerciseID == exercise.id && $0.completed }.count
    }
    public var loggedWorkCount: Int { entries.count + (activities ?? []).filter(\.completed).count }
    public var hasRecordedWork: Bool { !entries.isEmpty || (activities ?? []).contains { $0.elapsedSeconds > 0 } }
    public var latestWorkDate: Date { max(entries.last?.completedAt ?? startedAt, activities?.last?.endedAt ?? startedAt) }
}
