import Foundation
import Testing
@testable import WorkoutCore

struct FlexibilityTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func plan() -> WorkoutPlan {
        var a = ExercisePlan(name: "Row A", sets: 2, reps: 10, weight: 20, restSeconds: 60, comparisonID: "row-a", loadConvention: .machineStack)
        a.alternatives = [ExerciseAlternative(name: "Row B", comparisonID: "row-b", loadConvention: .machineStack, unit: .kg, reps: 8, weight: 15, restSeconds: 90)]
        var b = ExercisePlan(name: "Press", sets: 1, reps: 8, weight: 5, restSeconds: 60, comparisonID: "press-a", loadConvention: .perDumbbell)
        b.workPolicy = WorkPolicy(priority: 2, optional: false)
        var c = ExercisePlan(name: "Curl", sets: 1, reps: 10, weight: 5, restSeconds: 60, comparisonID: "curl-a", loadConvention: .perDumbbell)
        c.workPolicy = WorkPolicy(priority: 5, optional: true)
        return WorkoutPlan(title: "Generic", exercises: [a,b,c])
    }
    @Test func deferralPreservesSetsRestAndReturnsLater() throws {
        var session = try WorkoutSession(plan: plan(), now: start)
        try session.logSet(weight: 20, reps: 9, now: start.addingTimeInterval(10), uptime: 100)
        let entry = session.entries[0], deadline = session.restUntil
        try session.deferCurrent(now: start.addingTimeInterval(12))
        #expect(session.currentExercise?.name == "Press")
        #expect(session.restUntil == deadline && session.entries == [entry])
        session.skipRest(); try session.logSet(weight: 5, reps: 8, now: start.addingTimeInterval(80), uptime: 170)
        session.skipRest(); try session.logSet(weight: 5, reps: 10, now: start.addingTimeInterval(150), uptime: 240)
        session.skipRest(); #expect(session.currentExercise?.name == "Row A" && session.currentSetNumber == 2)
        try session.logSet(weight: 20, reps: 10, now: start.addingTimeInterval(220), uptime: 310)
        try session.validateCompleted()
        #expect(session.plan.exercises.first?.name == "Row A")
        #expect(session.report().contains("Deferred Row A"))
    }
    @Test func onlyApprovedSubstitutionBeforeAnySetAndUnitsMustMatch() throws {
        let p = plan(); var session = try WorkoutSession(plan: p, now: start)
        #expect(throws: (any Error).self) { try session.substituteCurrent(with: UUID()) }
        let alt = try #require(p.exercises[0].alternatives?.first)
        try session.substituteCurrent(with: alt.id, now: start)
        #expect(session.currentExercise?.name == "Row B")
        #expect(session.currentExercise?.comparisonID == "row-b")
        #expect(session.plan == p)
        try session.logSet(weight: 15, reps: 8, now: start.addingTimeInterval(5), uptime: 100)
        #expect(throws: (any Error).self) { try session.undoAdjustment() }
        #expect(throws: (any Error).self) { try session.substituteCurrent(with: alt.id) }
        session.finish(now: start.addingTimeInterval(10)); try session.validateCompleted()
        #expect(session.report().contains("Row B"))
        #expect(session.entries[0].exerciseID == alt.id)
    }
    @Test func optionalOmissionIsReviewedReversibleAndNeverChangesTargetsOrRest() throws {
        let p = plan(); var session = try WorkoutSession(plan: p, now: start)
        #expect(throws: (any Error).self) { try session.omitOptional([p.exercises[1].id]) }
        try session.omitOptional([p.exercises[2].id], now: start)
        #expect(session.plan == p)
        #expect(session.execution.omitted == [p.exercises[2].id])
        try session.undoAdjustment(now: start)
        #expect(session.execution.omitted.isEmpty)
        try session.omitOptional([p.exercises[2].id], now: start)
        try session.logSet(weight: 20, reps: 10, now: start.addingTimeInterval(10), uptime: 100)
        #expect(session.restDuration == 60)
        #expect(throws: (any Error).self) { try session.undoAdjustment() }
        #expect(session.entries.count == 1)
    }
    @Test func configurationAndOriginalSurviveRelaunch() throws {
        var session = try WorkoutSession(plan: plan(), now: start)
        try session.deferCurrent(now: start)
        let data = try FileRepository<WorkoutSession>.encoder().encode(session)
        let restored = try FileRepository<WorkoutSession>.decoder().decode(WorkoutSession.self, from: data)
        #expect(restored == session)
        #expect(restored.currentExercise?.name == "Press")
        #expect(restored.plan.exercises.first?.name == "Row A")
    }
    @Test func paceUsesMatchedIntervalsAndReportsUncertainty() throws {
        let p = plan(); var historical = try WorkoutSession(plan: p, now: start)
        let fresh = try WorkoutSession(plan: p, now: start.addingTimeInterval(1000))
        #expect(WorkoutPace.remaining(fresh, history: [], now: start).sampleCount == 0)
        try historical.logSet(weight: 20, reps: 10, now: start.addingTimeInterval(10), uptime: 100)
        historical.skipRest(); try historical.logSet(weight: 20, reps: 10, now: start.addingTimeInterval(100), uptime: 190)
        historical.finish(now: start.addingTimeInterval(100))
        let estimate = WorkoutPace.remaining(fresh, history: [historical], now: start)
        #expect(estimate.sampleCount == 1 && estimate.upper >= estimate.lower)
        var mismatched = p; mismatched.unit = .lb
        #expect(WorkoutPace.remaining(try WorkoutSession(plan: mismatched), history: [historical]).sampleCount == 0)
    }
    @Test func legacySessionHasNoInventedConfigurationOrTiming() throws {
        var session = try WorkoutSession(plan: plan(), now: start)
        try session.logSet(weight: 20, reps: 10, now: start, uptime: 100)
        var object = try JSONSerialization.jsonObject(with: FileRepository<WorkoutSession>.encoder().encode(session)) as! [String: Any]
        var entries = object["entries"] as! [[String: Any]]; entries[0].removeValue(forKey: "loggedUptime"); object["entries"] = entries
        let restored = try FileRepository<WorkoutSession>.decoder().decode(WorkoutSession.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.configuration == nil && restored.entries[0].loggedUptime == nil)
        #expect(restored.execution.order == restored.plan.exercises.map(\.id))
    }
    @Test func timeBudgetValidationAndDeadline() throws {
        let budget = TimeBudget(durationMinutes: 30); try budget.validate()
        #expect(budget.deadline(start: start) == start.addingTimeInterval(1800))
        #expect(throws: (any Error).self) { try TimeBudget(durationMinutes: 30, finishAt: start).validate() }
        #expect(throws: (any Error).self) { try TimeBudget(durationMinutes: 0).validate() }
    }
    @Test func deadlineProposalUsesApprovedPrioritiesAndStopsWhenItFits() throws {
        var p = plan()
        var extra = p.exercises[2]; extra.id = UUID(); extra.name = "Optional raise"; extra.workPolicy = WorkPolicy(priority: 3, optional: true)
        p.exercises.append(extra)
        p.timeBudget = TimeBudget(durationMinutes: 12)
        let session = try WorkoutSession(plan: p, now: start)
        let proposal = WorkoutPace.shorterProposal(session, history: [], now: start)
        #expect(proposal.map(\.name) == ["Curl"])
        #expect(session.configuration == nil)
        p.timeBudget = TimeBudget(durationMinutes: 30)
        #expect(WorkoutPace.shorterProposal(try WorkoutSession(plan: p, now: start), history: [], now: start).isEmpty)
    }
    @Test func oversizedAlternativesRejectedBeforeSavingAndChangesReserveDeliverySpace() throws {
        var p = plan()
        p.exercises = (0..<50).map { _ in
            var e = ExercisePlan(name: String(repeating: "x", count: 120), sets: 4, reps: 10, weight: 20)
            e.alternatives = (0..<5).map { _ in ExerciseAlternative(name: String(repeating: "y", count: 120), comparisonID: String(repeating: "a", count: 64), loadConvention: .total, unit: .kg, reps: 10, weight: 20, restSeconds: 60) }; return e
        }
        #expect(throws: (any Error).self) { try p.validate() }
        var session = try WorkoutSession(plan: plan(), now: start)
        for i in 0..<80 {
            do { try session.deferCurrent(now: start.addingTimeInterval(Double(i))) } catch { break }
        }
        while session.phase != .completed {
            session.skipRest(); try session.logSet(weight: 1000, reps: 200, now: start.addingTimeInterval(200), uptime: 1000)
        }
        #expect(try SyncCodec.encode(.completed(session)).count < 60_000)
    }

}
