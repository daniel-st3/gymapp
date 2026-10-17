import Foundation
import Testing
@testable import WorkoutCore

struct PaceAccountingTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func plan(sets: Int = 2) -> WorkoutPlan {
        WorkoutPlan(title: "Generic", exercises: [ExercisePlan(name: "Row", sets: sets, reps: 10, weight: 20, restSeconds: 60, comparisonID: "row-a", loadConvention: .machineStack)])
    }
    @Test func restCountIsExactAndExtensionsCountOnce() throws {
        var session = try WorkoutSession(plan: plan(), now: start)
        let initial = WorkoutPace.remaining(session, history: [], now: start)
        #expect(initial.lower == 110 && initial.upper == 300) // two work estimates, one rest
        try session.logSet(weight: 20, reps: 10, now: start.addingTimeInterval(25), uptime: 100)
        let during = WorkoutPace.remaining(session, history: [], now: start.addingTimeInterval(35))
        #expect(during.lower == 75 && during.upper == 170) // 50 rest + last work estimate
        try session.extendRest(by: 30)
        let extended = WorkoutPace.remaining(session, history: [], now: start.addingTimeInterval(35))
        #expect(extended.lower == during.lower + 30)
        session.skipRest(now: start.addingTimeInterval(40))
        #expect(WorkoutPace.remaining(session, history: [], now: start.addingTimeInterval(40)).lower == 25)
        try session.logSet(weight: 20, reps: 10, now: start.addingTimeInterval(80), uptime: 155)
        #expect(WorkoutPace.remaining(session, history: [], now: start.addingTimeInterval(80)).upper == 0)
    }
    @Test func pendingChangeIsIncludedAndNoRestAfterFinalSet() throws {
        var p = plan(sets: 1); p.exercises.append(ExercisePlan(name: "Curl", sets: 1, reps: 10, weight: 5, restSeconds: 90)); p.transitionSeconds = 30
        var s = try WorkoutSession(plan: p, now: start)
        try s.logSet(weight: 20, reps: 10, now: start.addingTimeInterval(25), uptime: 100)
        #expect(WorkoutPace.remaining(s, history: [], now: start.addingTimeInterval(25)).lower == 115) // 60+30+25
        s.skipRest(now: start.addingTimeInterval(35))
        #expect(WorkoutPace.remaining(s, history: [], now: start.addingTimeInterval(45)).lower == 45) // 20+25
    }
    @Test func practiceFutureAndIncompleteHistoryCannotDrivePace() throws {
        var prior = try WorkoutSession(plan: plan(), now: start)
        try prior.logSet(weight: 20, reps: 10, now: start.addingTimeInterval(25), uptime: 100)
        prior.skipRest(); try prior.logSet(weight: 20, reps: 10, now: start.addingTimeInterval(115), uptime: 190)
        let current = try WorkoutSession(plan: plan(), now: start.addingTimeInterval(1000))
        #expect(WorkoutPace.remaining(current, history: [prior]).sampleCount == 1)
        var practicePlan = plan(); practicePlan.practice = true
        var practice = try WorkoutSession(plan: practicePlan, now: start)
        practice.finish(now: start.addingTimeInterval(200))
        let incomplete = try WorkoutSession(plan: plan(), now: start)
        var future = try WorkoutSession(plan: plan(), now: start.addingTimeInterval(2000))
        future.finish(now: start.addingTimeInterval(2100))
        #expect(WorkoutPace.remaining(current, history: [practice, incomplete, future]).sampleCount == 0)
    }
}
