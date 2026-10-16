import Foundation
import Testing
@testable import WorkoutCore

struct WorkoutCoreTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func plan(sets: Int = 2, rest: Int = 60) -> WorkoutPlan {
        WorkoutPlan(title: "Test workout", exercises: [ExercisePlan(name: "Bench press", sets: sets, reps: 10, weight: 40, restSeconds: rest)])
    }

    @Test func importsCoachJSONAndFencedReply() throws {
        let direct = try PlanImport.parse(PlanImport.example)
        let fenced = try PlanImport.parse("```json\n\(PlanImport.example)\n```")
        #expect(direct.title == "Upper body")
        #expect(direct.exercises.count == fenced.exercises.count)
        #expect(direct.totalSets == 9)
    }

    @Test func rejectsMalformedMissingAndUnsafeValues() {
        for input in ["", "Bench press 3x10", "{}", "{\"title\":\"x\"}",
                      PlanImport.example.replacingOccurrences(of: "\"kg\"", with: "\"lbs\""),
                      PlanImport.example.replacingOccurrences(of: "\"sets\": 3", with: "\"sets\": 9223372036854775807"),
                      PlanImport.example.replacingOccurrences(of: "\"reps\": 10", with: "\"reps\": 0"),
                      PlanImport.example.replacingOccurrences(of: "\"weight\": 40", with: "\"weight\": -1"),
                      String(repeating: "x", count: 64_001)] {
            #expect(throws: (any Error).self) { try PlanImport.parse(input) }
        }
    }

    @Test func rejectsDuplicateExerciseIDsAndExcessiveSets() {
        let exercise = ExercisePlan(name: "Row", sets: 20, reps: 10, weight: 0)
        #expect(throws: (any Error).self) { try WorkoutPlan(title: "x", exercises: [exercise, exercise]).validate() }
        let exercises = (1...11).map { ExercisePlan(name: "Row \($0)", sets: 20, reps: 10, weight: 0) }
        #expect(throws: (any Error).self) { try WorkoutPlan(title: "x", exercises: exercises).validate() }
    }

    @Test func recordsActualValuesAndPreventsDoubleLoggingDuringRest() throws {
        var workout = try WorkoutSession(plan: plan(), now: start)
        try workout.logSet(weight: 42.5, reps: 8, now: start.addingTimeInterval(20))
        #expect(workout.entries.first?.weight == 42.5)
        #expect(workout.entries.first?.reps == 8)
        #expect(workout.currentSetNumber == 2)
        #expect(workout.phase == .resting)
        #expect(throws: (any Error).self) { try workout.logSet(weight: 42.5, reps: 8) }
    }

    @Test func restUsesAnAbsoluteDeadlineAndOnlyCompletesOnce() throws {
        var workout = try WorkoutSession(plan: plan(), now: start)
        try workout.logSet(weight: 40, reps: 10, now: start)
        #expect(workout.restUntil == start.addingTimeInterval(60))
        let beforeDeadline = workout.endRestIfDue(now: start.addingTimeInterval(59))
        #expect(!beforeDeadline)
        let afterDeadline = workout.endRestIfDue(now: start.addingTimeInterval(600))
        #expect(afterDeadline)
        #expect(workout.phase == .active)
        let duplicate = workout.endRestIfDue(now: start.addingTimeInterval(601))
        #expect(!duplicate)
    }

    @Test func extendingAndSkippingRest() throws {
        var workout = try WorkoutSession(plan: plan(), now: start)
        try workout.logSet(weight: 40, reps: 10, now: start)
        try workout.extendRest()
        #expect(workout.restUntil == start.addingTimeInterval(90))
        workout.skipRest()
        #expect(workout.restUntil == nil)
        #expect(throws: (any Error).self) { try workout.extendRest() }
    }

    @Test func undoReopensTheCorrectSet() throws {
        var workout = try WorkoutSession(plan: plan(), now: start)
        try workout.logSet(weight: 40, reps: 10, now: start)
        try workout.undoLastSet()
        #expect(workout.entries.isEmpty)
        #expect(workout.currentSetNumber == 1)
        #expect(workout.phase == .active)
        #expect(workout.restUntil == nil)
    }

    @Test func movesToNextExerciseAndFinishesWithoutFinalRest() throws {
        let a = ExercisePlan(name: "Row", sets: 1, reps: 10, weight: 20, restSeconds: 30)
        let b = ExercisePlan(name: "Press", sets: 1, reps: 8, weight: 10, restSeconds: 60)
        var workout = try WorkoutSession(plan: WorkoutPlan(title: "Upper", exercises: [a, b]), now: start)
        try workout.logSet(weight: 20, reps: 10, now: start)
        #expect(workout.currentExercise?.id == b.id)
        workout.skipRest()
        try workout.logSet(weight: 10, reps: 8, now: start.addingTimeInterval(60))
        #expect(workout.phase == .completed)
        #expect(workout.restUntil == nil)
        #expect(workout.volume == 280)
        try workout.validateCompleted()
    }

    @Test func zeroRestAndBodyweightWorkouts() throws {
        var workout = try WorkoutSession(plan: plan(rest: 0), now: start)
        try workout.logSet(weight: 0, reps: 10, now: start)
        #expect(workout.phase == .active)
        try workout.logSet(weight: 0, reps: 8, now: start.addingTimeInterval(30))
        #expect(workout.phase == .completed)
        #expect(workout.volume == 0)
    }

    @Test func invalidActualValuesDoNotMutateTheSession() throws {
        var workout = try WorkoutSession(plan: plan(), now: start)
        #expect(throws: (any Error).self) { try workout.logSet(weight: .nan, reps: 10, now: start) }
        #expect(throws: (any Error).self) { try workout.logSet(weight: 0, reps: 0, now: start) }
        #expect(throws: (any Error).self) { try workout.logSet(weight: 0, reps: 2, now: start.addingTimeInterval(-1)) }
        #expect(workout.entries.isEmpty)
    }

    @Test func endingEarlyDoesNotInventCompletedSets() throws {
        var workout = try WorkoutSession(plan: plan(), now: start)
        try workout.logSet(weight: 40, reps: 6, now: start)
        workout.finish(now: start.addingTimeInterval(70))
        let report = workout.report()
        #expect(report.contains("Completed: 1 / 2 sets"))
        #expect(report.contains("6 reps"))
        #expect(!report.contains("10 reps"))
        try workout.validateCompleted()
    }

    @Test func rejectsActiveSessionsAtThePhoneBoundary() throws {
        let active = try WorkoutSession(plan: plan(), now: start)
        var phone = PhoneState()
        #expect(throws: (any Error).self) { try phone.receive(active) }
        #expect(phone.sessions.isEmpty)
    }

    @Test func completeImportLogPersistDeliverAcknowledgeReportFlow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileRepository<WatchState>(url: directory.appendingPathComponent("watch.json"))
        let imported = try PlanImport.parse(PlanImport.example)
        var watch = WatchState()
        watch.plan = imported
        watch.session = try WorkoutSession(plan: imported, now: start)
        try watch.session?.logSet(weight: 42.5, reps: 8, now: start)
        try repository.save(watch)
        // Simulate process termination and relaunch while resting.
        watch = try #require(try repository.load())
        #expect(watch.session?.phase == .resting)
        #expect(watch.session?.restUntil == start.addingTimeInterval(90))
        watch.session?.finish(now: start.addingTimeInterval(200))
        watch.enqueueCompleted(); watch.enqueueCompleted()
        #expect(watch.outbox.count == 1)
        let data = try SyncCodec.encode(.completed(try #require(watch.outbox.first)))
        guard case .completed(let received) = try SyncCodec.decode(data) else { Issue.record("Wrong packet"); return }
        var phone = PhoneState()
        try phone.receive(received); try phone.receive(received) // duplicate background delivery
        #expect(phone.sessions.count == 1)
        #expect(phone.sessions.first?.entries.first?.weight == 42.5)
        #expect(phone.sessions.first?.entries.first?.reps == 8)
        #expect(phone.sessions.first?.report().contains("\(WorkoutSession.number(42.5)) kg × 8 reps") == true)
        let context = try SyncCodec.encode(.snapshot(PhoneSnapshot(plan: imported, acknowledged: phone.sessions.map(\.id))))
        guard case .snapshot(let snapshot) = try SyncCodec.decode(context) else { Issue.record("Wrong snapshot"); return }
        watch.acknowledge(snapshot.acknowledged)
        #expect(watch.outbox.isEmpty)
        #expect(watch.recent.count == 1)
    }

    @Test func aNewPlanDoesNotChangeAnActiveWorkoutsSnapshot() throws {
        var watch = WatchState()
        watch.plan = plan()
        watch.session = try WorkoutSession(plan: try #require(watch.plan), now: start)
        let activeID = watch.session?.plan.id
        watch.plan = try PlanImport.parse(PlanImport.example)
        #expect(watch.session?.plan.id == activeID)
        #expect(watch.plan?.id != activeID)
    }

    @Test func unacknowledgedWorkoutsSurviveRelaunch() throws {
        var workout = try WorkoutSession(plan: plan(sets: 1), now: start)
        try workout.logSet(weight: 40, reps: 10, now: start)
        var watch = WatchState(); watch.session = workout; watch.enqueueCompleted()
        let data = try FileRepository<WatchState>.encoder().encode(watch)
        let restored = try FileRepository<WatchState>.decoder().decode(WatchState.self, from: data)
        #expect(restored.outbox.map(\.id) == [workout.id])
    }

    @Test func malformedStorageThrowsInsteadOfReturningEmptyHistory() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not JSON".utf8).write(to: file)
        #expect(throws: (any Error).self) { try FileRepository<PhoneState>(url: file).load() }
        #expect(try String(contentsOf: file, encoding: .utf8) == "not JSON")
    }

    @Test func shortcutReviewRequiresAnalysisAndValidPlan() throws {
        let json = "{\"analysis\":\"Keep the load steady.\",\"plan\":\(PlanImport.example)}"
        let review = try PlanImport.parseReview(json)
        #expect(review.analysis == "Keep the load steady.")
        #expect(review.plan.totalSets == 9)
        #expect(throws: (any Error).self) { try PlanImport.parseReview(PlanImport.example) }
    }

    @Test func reviewContextIncludesExplicitHistoryAndProfile() throws {
        var session = try WorkoutSession(plan: plan(), now: start)
        session.finish(now: start)
        let prompt = PlanImport.reviewPrompt(profile: "Prefer machines. Load is per dumbbell.", sessions: [session])
        #expect(prompt.contains("Prefer machines"))
        #expect(prompt.contains(session.id.uuidString))
        #expect(prompt.contains("Do not assume access"))
    }

    @Test func worstCaseAllowedWorkoutFitsTheTransport() throws {
        // Quote characters require JSON escaping. Fifty entries maximize plan overhead.
        let exercises = (0..<50).map { _ in ExercisePlan(name: String(repeating: "\"", count: 120), sets: 4, reps: 200, weight: 1000, restSeconds: 0) }
        var session = try WorkoutSession(plan: WorkoutPlan(title: String(repeating: "y", count: 120), exercises: exercises), now: start)
        for index in 0..<200 { try session.logSet(weight: 1000, reps: 200, now: start.addingTimeInterval(Double(index))) }
        #expect(try SyncCodec.encode(.completed(session)).count < 60_000)
    }
}
