import Foundation

/// Read-only projections of confirmed logs. Never edits prescriptions or history.
public struct TrainingAnalytics: Sendable {
    public struct Week: Identifiable, Sendable {
        public let start: Date
        public let workouts: Int
        public let sets: Int
        public var id: Date { start }
    }
    public struct Variation: Hashable, Sendable {
        public let comparisonID: String
        public let unit: WeightUnit
        public let convention: LoadConvention
    }
    public struct Result: Identifiable, Sendable {
        public let session: WorkoutSession
        public let entries: [CompletedSet]
        public var id: UUID { session.id }
        public func bestSet(reps: Int, convention: LoadConvention) -> CompletedSet? {
            let matching = entries.filter { $0.reps == reps }
            if convention == .assistance { return matching.min { $0.weight < $1.weight } }
            return matching.max { $0.weight < $1.weight }
        }
    }
    public struct Exercise: Identifiable, Sendable {
        public let key: Variation
        public let name: String
        public let results: [Result] // newest first; one result per session
        public var id: Variation { key }
        public var repetitionCounts: [Int] { Array(Set(results.flatMap { $0.entries.map(\.reps) })).sorted() }
    }
    public let start: Date
    public let end: Date
    public let weeks: [Week]
    public let sessions: [WorkoutSession]
    public let exercises: [Exercise]
    public let setCount: Int
    public let repCount: Int
    public let trainingDays: Int
    public let medianMinutes: Int?
    public let excludedDurations: Int
    public let unmatchedSets: Int
    public let importedCount: Int

    public init(state: PhoneState, weekCount: Int = 4, now: Date = Date(), calendar: Calendar = .current) {
        var calendar = calendar; calendar.firstWeekday = 2
        let count = min(12, max(1, weekCount))
        let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .weekOfYear, value: -(count - 1), to: current) ?? current
        self.start = start; end = now
        var seen = Set<UUID>()
        let records = state.sessions.filter {
            $0.phase == .completed && $0.hasRecordedWork && $0.plan.practice != true && $0.startedAt >= start &&
            $0.startedAt <= now && ($0.endedAt.map { $0 <= now } ?? false) && seen.insert($0.id).inserted
        }.sorted { $0.startedAt > $1.startedAt }
        sessions = records
        setCount = records.reduce(0) { $0 + $1.entries.count }
        repCount = records.reduce(0) { $0 + $1.entries.reduce(0) { $0 + $1.reps } }
        trainingDays = Set(records.map { calendar.startOfDay(for: $0.startedAt) }).count
        let durations = records.map(\.duration).filter { $0 > 0 && $0 <= 6 * 3600 && $0.isFinite }.sorted()
        excludedDurations = records.count - durations.count
        if durations.isEmpty { medianMinutes = nil }
        else {
            let middle = durations.count / 2
            let median = durations.count.isMultiple(of: 2) ? (durations[middle - 1] + durations[middle]) / 2 : durations[middle]
            medianMinutes = Int((median / 60).rounded())
        }
        weeks = (0..<count).compactMap { offset in
            guard let day = calendar.date(byAdding: .weekOfYear, value: offset, to: start),
                  let next = calendar.date(byAdding: .weekOfYear, value: 1, to: day) else { return nil }
            let week = records.filter { $0.startedAt >= day && $0.startedAt < next }
            return Week(start: day, workouts: week.count, sets: week.reduce(0) { $0 + $1.entries.count })
        }
        var grouped: [Variation: (name: String, results: [Result])] = [:]
        var unmatched = 0
        for session in records {
            var sets: [Variation: [CompletedSet]] = [:]
            for entry in session.entries {
                guard let exercise = session.executionExercises.first(where: { $0.id == entry.exerciseID }),
                      let variation = exercise.comparisonID, let convention = exercise.loadConvention else { unmatched += 1; continue }
                let key = Variation(comparisonID: variation, unit: session.plan.unit, convention: convention)
                if grouped[key] == nil { grouped[key] = (exercise.name, []) }
                sets[key, default: []].append(entry)
            }
            for (key, values) in sets { grouped[key]?.results.append(Result(session: session, entries: values)) }
        }
        unmatchedSets = unmatched
        exercises = grouped.map { Exercise(key: $0.key, name: $0.value.name, results: $0.value.results) }
            .sorted { a, b in
                let left = a.results.first?.session.startedAt ?? .distantPast, right = b.results.first?.session.startedAt ?? .distantPast
                if left != right { return left > right }
                return "\(a.name)|\(a.key.comparisonID)|\(a.key.unit.rawValue)|\(a.key.convention.rawValue)" < "\(b.name)|\(b.key.comparisonID)|\(b.key.unit.rawValue)|\(b.key.convention.rawValue)"
            }
        importedCount = state.externalHistory.filter { $0.parsedDate.map { $0 >= start && $0 <= now } ?? false }.count
    }
}
