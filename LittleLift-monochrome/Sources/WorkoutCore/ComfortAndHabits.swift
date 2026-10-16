import Foundation

public struct ComfortPreferences: Codable, Equatable, Sendable {
    public var revision: UUID? = nil
    public var haptics: Bool? = nil
    public var restHaptics = true
    public var rhythmEnabled = false
    public var rhythmSeconds = 3
    public var reminderHaptics = false
    public var waterMinutes: Int? = nil
    public var quietFeedback = false
    public var language: String? = nil
    public init() {}
    public func validate() throws {
        guard (2...10).contains(rhythmSeconds), waterMinutes.map({ (10...120).contains($0) }) ?? true,
              language == nil || ["en", "es"].contains(language!) else { throw WorkoutError.invalidInput(L10n.s("Choose a supported language, 2–10 second rhythm and 10–120 minute reminder interval.")) }
    }
}
public struct WeeklyGoal: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let effectiveWeek: Date
    public let minimumDays: Int
    public let paused: Bool
    public init(effectiveWeek: Date, minimumDays: Int, paused: Bool = false) { id = UUID(); self.effectiveWeek = effectiveWeek; self.minimumDays = minimumDays; self.paused = paused }
}
public struct WeeklyHabit: Codable, Equatable, Sendable {
    public let timeZone: String
    public var goals: [WeeklyGoal]
    public init(timeZone: String, goals: [WeeklyGoal]) { self.timeZone = timeZone; self.goals = goals }
    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4
        c.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0)!; return c
    }
    public func week(_ date: Date) -> Date { calendar.dateInterval(of: .weekOfYear, for: date)!.start }
    public func goal(at week: Date) -> WeeklyGoal? { goals.filter { $0.effectiveWeek <= week }.max { $0.effectiveWeek < $1.effectiveWeek } }
    /// Existing rules are immutable for current/past weeks. Zone remains pinned,
    /// so travel and device clock-zone changes cannot rewrite earlier weeks.
    public mutating func schedule(days: Int, paused: Bool, now: Date) throws {
        guard (1...7).contains(days), goals.count < 520 else { throw WorkoutError.invalidInput(L10n.s("Choose 1–7 days per week.")) }
        let start = goals.isEmpty ? week(now) : calendar.date(byAdding: .weekOfYear, value: 1, to: week(now))!
        goals.removeAll { $0.effectiveWeek == start }
        goals.append(WeeklyGoal(effectiveWeek: start, minimumDays: days, paused: paused))
    }
    public func days(in week: Date, sessions: [WorkoutSession], now: Date) -> Int {
        let end = calendar.date(byAdding: .weekOfYear, value: 1, to: week)!
        var ids = Set<UUID>(); var days = Set<Date>()
        for session in sessions where session.phase == .completed && session.plan.practice != true && session.hasRecordedWork && session.startedAt >= week && session.startedAt < end && (session.endedAt ?? .distantFuture) <= now && ids.insert(session.id).inserted {
            days.insert(calendar.startOfDay(for: session.startedAt))
        }
        return days.count
    }
    public func streak(sessions: [WorkoutSession], now: Date) -> Int {
        let current = week(now); var cursor = current; var total = 0
        // Current incomplete week stays open; paused weeks bridge continuity but
        // never earn a completed week. Missing a finished week ends the streak.
        for _ in 0..<520 {
            guard let rule = goal(at: cursor) else { break }
            if !rule.paused {
                if days(in: cursor, sessions: sessions, now: now) >= rule.minimumDays { total += 1 }
                else if cursor != current { break }
            }
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor)!
        }
        return total
    }
}

public enum FactualFeedback {
    public static func message(for session: WorkoutSession, previous: [WorkoutSession]) -> String {
        for exercise in session.executionExercises where exercise.kind == .strength {
            guard let current = session.entries.last(where: { $0.exerciseID == exercise.id }),
                  let prior = Progression.lastResult(for: exercise, unit: session.plan.unit, sessions: previous.filter { $0.id != session.id && $0.startedAt < session.startedAt && $0.plan.practice != true }),
                  current.weight == prior.entry.weight, current.reps > prior.entry.reps else { continue }
            if current.reps - prior.entry.reps == 1 { return L10n.s("\(exercise.name): one more rep at the same load than your previous matching final set.") }
            return L10n.s("\(exercise.name): \(current.reps - prior.entry.reps) more reps at the same load than your previous matching final set.")
        }
        return L10n.s("\(session.loggedWorkCount) of \(session.plan.totalSets) prescribed sets / segments logged.")
    }
}
