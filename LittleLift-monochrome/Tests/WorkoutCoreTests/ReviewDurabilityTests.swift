import Foundation
import Testing
@testable import WorkoutCore

struct ReviewDurabilityTests {
    let helper = ReviewQueueTests()
    @Test func reviewInputIncludesOriginalIdentifiersAndMeasuredIntervals() throws {
        var state = PhoneState()
        var exercise = ExercisePlan(name: "Generic row", sets: 2, reps: 10, weight: 20, restSeconds: 60)
        exercise.comparisonID = "generic-row"; exercise.loadConvention = .machineStack
        let plan = WorkoutPlan(title: "Original prescription", exercises: [exercise])
        var session = try WorkoutSession(plan: plan, now: helper.now)
        try session.logSet(weight: 20, reps: 9, now: helper.now.addingTimeInterval(20), uptime: 100)
        session.skipRest(now: helper.now.addingTimeInterval(80))
        try session.logSet(weight: 20, reps: 9, now: helper.now.addingTimeInterval(110), uptime: 190)
        try state.receive(session)
        let ticket = try state.beginReview(now: helper.now.addingTimeInterval(120))
        let prompt = try state.prompt(for: ticket)
        #expect(prompt.contains(exercise.id.uuidString))
        #expect(prompt.contains("SOURCE PRESCRIPTION"))
        #expect(prompt.contains("Log-tap interval: 90 s. Includes exercise time; not actual rest."))
        #expect(prompt.contains("do not copy its title, IDs"))
        #expect(state.sessions.first?.plan == plan)
    }
    @Test func feedbackSurvivesAcceptanceDiscardRelaunchAndNextWorkout() throws {
        var state = PhoneState()
        let first = try helper.completed(), second = try helper.completed()
        try state.receive(first); try state.receive(second)
        let a = try state.beginReview(sessionID: first.id, now: helper.now)
        try state.receiveReview(helper.response(a), now: helper.now.addingTimeInterval(1))
        let originalProposal = state.review
        let b = try state.beginReview(sessionID: second.id, now: helper.now.addingTimeInterval(2))
        try state.receiveReview(helper.response(b).replacingOccurrences(of: "Generic descriptive feedback", with: "A second response"), now: helper.now.addingTimeInterval(3))
        #expect(state.review == originalProposal)
        #expect(state.reviewQueue.allSatisfy { $0.result != nil && $0.status == .received })
        #expect(throws: (any Error).self) { try state.stageSavedReview(for: second.id) }
        try state.acceptReview()
        let accepted = state.plan
        try state.stageSavedReview(for: second.id)
        state.discardReview() // explicit discard leaves the archived response intact
        var restored = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(state))
        #expect(restored.plan == accepted && restored.reviewQueue == state.reviewQueue)
        try restored.receiveReview(helper.response(b), now: helper.now.addingTimeInterval(4))
        #expect(restored.review == nil) // duplicate delivery cannot re-open a dismissed proposal
        try restored.stageSavedReview(for: second.id)
        #expect(restored.review?.analysis == "A second response")
        #expect(restored.sessions == state.sessions)
    }
    @Test func manualFeedbackIsRetainedWithoutInventingAWorkoutAssociation() throws {
        var state = PhoneState()
        let response = TrainingReview(analysis: "Imported coach feedback", plan: try PlanImport.parse(PlanImport.example))
        try state.propose(response); state.discardReview()
        #expect(state.unlinkedCoachReviews?.first?.response == response)
        try state.propose(response); try state.acceptReview()
        #expect(state.unlinkedCoachReviews?.count == 1)
        #expect(state.reviewJobs == nil && state.sessions.isEmpty)
    }
    @Test func legacyJobsDecodeWithoutFabricatingFeedback() throws {
        let id = UUID()
        let json = "{\"id\":\"\(id)\",\"status\":\"received\"}"
        let job = try FileRepository<ReviewJob>.decoder().decode(ReviewJob.self, from: Data(json.utf8))
        #expect(job.result == nil && job.receivedAt == nil)
    }
    @Test func importsCannotSilentlyReplaceAnUnacceptedProposal() throws {
        var state = PhoneState()
        let first = TrainingReview(analysis: "First", plan: try PlanImport.parse(PlanImport.example))
        let second = TrainingReview(analysis: "Second", plan: first.plan)
        try state.propose(first); try state.propose(first)
        #expect(throws: (any Error).self) { try state.propose(second) }
        #expect(state.review == first && state.plan == nil)
    }
    @Test func sharedFilesAreBoundedLocalAndReceiptAware() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("workout.json")
        try PlanImport.example.write(to: file, atomically: true, encoding: .utf8)
        #expect(try WorkoutFileImport.readText(file) == PlanImport.example)
        try String(repeating: "a", count: 64_001).write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try WorkoutFileImport.readText(file) }
        try "{\"reviewSessionID\":\"bad\"}".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try WorkoutFileImport.readText(file) }
        #expect(throws: (any Error).self) { try WorkoutFileImport.readText(URL(string: "https://example.invalid/workout")!) }
    }
}
