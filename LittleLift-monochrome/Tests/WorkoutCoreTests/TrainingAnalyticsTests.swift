import Foundation
import Testing
@testable import WorkoutCore

struct TrainingAnalyticsTests {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private var now: Date { ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z")! }
    private func session(days: Int = 0, weights: [Double] = [10, 12], reps: [Int] = [8, 8], unit: WeightUnit = .kg, convention: LoadConvention? = .perDumbbell, variation: String? = "press-a", duration: Double = 120) throws -> WorkoutSession {
        let start = now.addingTimeInterval(Double(-days * 86400) - 300)
        let plan = WorkoutPlan(title: "Generic workout", unit: unit, exercises: [ExercisePlan(name: "Press", sets: 3, reps: 10, weight: 20, restSeconds: 0, comparisonID: variation, loadConvention: convention)])
        var s = try WorkoutSession(plan: plan, now: start)
        for (i, weight) in weights.enumerated() { try s.logSet(weight: weight, reps: reps[i], now: start.addingTimeInterval(Double(i + 1))) }
        s.finish(now: start.addingTimeInterval(duration)); return s
    }
    @Test func emptyIsUnknownNotInventedProgress() {
        let a = TrainingAnalytics(state: PhoneState(), now: now, calendar: calendar)
        #expect(a.weeks.count == 4 && a.setCount == 0 && a.medianMinutes == nil && a.exercises.isEmpty)
        #expect(a.weeks.allSatisfy { $0.sets == 0 })
    }
    @Test func usesActualSetsEarlyFinishesAndDeduplicates() throws {
        var state = PhoneState(); let first = try session(); let second = try session(days: 1, weights: [9], reps: [7], duration: 240)
        state.sessions = [first, second, first]
        let a = TrainingAnalytics(state: state, now: now, calendar: calendar)
        #expect(a.sessions.count == 2 && a.setCount == 3 && a.repCount == 23 && a.trainingDays == 2)
        #expect(a.medianMinutes == 3)
        #expect(a.weeks.reduce(0) { $0 + $1.sets } == 3)
        #expect(a.exercises.count == 1 && a.exercises[0].results.count == 2)
        #expect(a.exercises[0].results[0].bestSet(reps: 8, convention: .perDumbbell)?.weight == 12)
        #expect(a.exercises[0].results[0].bestSet(reps: 7, convention: .perDumbbell) == nil)
    }
    @Test func doesNotMergeNamesUnitsConventionsOrImportedHistory() throws {
        var state = PhoneState()
        state.sessions = [try session(), try session(unit: .lb), try session(convention: .total), try session(variation: "press-b"), try session(convention: nil, variation: nil)]
        try state.importHistory(HistoryImport.parse(HistoryImport.example))
        let a = TrainingAnalytics(state: state, now: now, calendar: calendar)
        #expect(a.exercises.count == 4 && a.unmatchedSets == 2 && a.setCount == 10 && a.importedCount == 1)
        #expect(a.exercises.allSatisfy { $0.results.count == 1 })
    }
    @Test func assistanceUsesLowerSettingWithoutTreatingItAsLiftedLoad() throws {
        var state = PhoneState(); state.sessions = [try session(weights: [30, 25], convention: .assistance)]
        let e = try #require(TrainingAnalytics(state: state, now: now, calendar: calendar).exercises.first)
        #expect(e.results[0].bestSet(reps: 8, convention: .assistance)?.weight == 25)
    }
    @Test func rangeIsCalendarBasedAndDoesNotIncludeFutureOrEmptySessions() throws {
        var state = PhoneState(); state.sessions = [try session(days: 21), try session(days: 30), try session(days: -1), try session(weights: [], reps: [])]
        let four = TrainingAnalytics(state: state, now: now, calendar: calendar)
        let twelve = TrainingAnalytics(state: state, weekCount: 12, now: now, calendar: calendar)
        #expect(four.sessions.count == 1 && twelve.sessions.count == 2)
        #expect(calendar.component(.weekday, from: four.start) == 2)
        #expect(four.start == ISO8601DateFormatter().date(from: "2026-09-21T00:00:00Z"))
    }
    @Test func projectionsDoNotMutateHistoryAndExcludeAbandonedElapsedTimes() throws {
        var state = PhoneState(); state.sessions = [try session(days: 1, duration: 7 * 3600), try session()]
        let data = try FileRepository<PhoneState>.encoder().encode(state)
        let a = TrainingAnalytics(state: state, now: now, calendar: calendar)
        #expect(a.excludedDurations == 1 && a.medianMinutes == 2 && a.setCount == 4)
        #expect(try FileRepository<PhoneState>.encoder().encode(state) == data)
        let restored = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: data)
        #expect(TrainingAnalytics(state: restored, now: now, calendar: calendar).setCount == a.setCount)
    }
}
