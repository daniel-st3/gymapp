import Foundation
import Testing
@testable import WorkoutCore

struct AutomaticReviewTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    func workout(at time: Date, variation: String? = "row-a", convention: LoadConvention? = .machineStack, unit: WeightUnit = .kg, weight: Double = 20, reps: Int = 9, practice: Bool = false) throws -> WorkoutSession {
        var exercise = ExercisePlan(name: "Row", sets: 2, reps: 10, weight: 20, restSeconds: 0)
        exercise.comparisonID = variation; exercise.loadConvention = convention
        var plan = WorkoutPlan(title: "Generic review", unit: unit, exercises: [exercise]); plan.practice = practice
        var session = try WorkoutSession(plan: plan, now: time)
        try session.logSet(weight: weight, reps: reps, now: time.addingTimeInterval(20), uptime: 100)
        session.finish(now: time.addingTimeInterval(21)); return session
    }
    @Test func reviewSurvivesDuplicateDeliveryRelaunchAndExternalFailure() throws {
        var state = PhoneState(); let session = try workout(at: date)
        try state.receive(session); let original = state
        try state.receive(session); #expect(state == original)
        let restored = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(state))
        let review = try #require(restored.localReview(for: session.id))
        #expect(review.strengthSets == 1 && review.matchedSets == 0 && review.timedSegments == 0)
        _ = try state.beginReview(now: date)
        try state.endReview(session.id, cancelled: true, detail: "Cancelled")
        #expect(state.localReview(for: session.id)?.summary == review.summary)
        #expect(state.sessions == original.sessions && state.plan == original.plan)
    }
    @Test func comparisonsUseActualValuesAndExactVariationUnitConvention() throws {
        let current = try workout(at: date, weight: 21.5, reps: 8)
        let prior = try workout(at: date.addingTimeInterval(-300), weight: 19.5, reps: 9)
        let wrongMachine = try workout(at: date.addingTimeInterval(-200), variation: "row-b", weight: 100)
        let wrongUnit = try workout(at: date.addingTimeInterval(-150), unit: .lb, weight: 40)
        let wrongConvention = try workout(at: date.addingTimeInterval(-100), convention: .total, weight: 80)
        let review = WorkoutEvidenceReview(session: current, history: [prior, wrongMachine, wrongUnit, wrongConvention])
        let comparison = try #require(review.comparisons.first)
        #expect(comparison.previous?.weight == 19.5 && comparison.previous?.reps == 9)
        #expect(comparison.previousSessionID == prior.id)
        #expect(comparison.exercise.weight == 20 && comparison.entry.weight == 21.5)
    }
    @Test func noFuturePracticeNameOnlyOrIncompleteBaseline() throws {
        let current = try workout(at: date)
        let future = try workout(at: date.addingTimeInterval(100))
        let practice = try workout(at: date.addingTimeInterval(-100), practice: true)
        var active = try WorkoutSession(plan: current.plan, now: date.addingTimeInterval(-200))
        try active.logSet(weight: 20, reps: 9, now: date.addingTimeInterval(-180))
        let unknown = try workout(at: date.addingTimeInterval(-300), variation: nil, convention: nil)
        #expect(WorkoutEvidenceReview(session: current, history: [future, practice, active, unknown]).matchedSets == 0)
        #expect(WorkoutEvidenceReview(session: practice, history: [try workout(at: date.addingTimeInterval(-500))]).matchedSets == 0)
    }
    @Test func laterArrivalOfEarlierHistoryUpdatesOnlyDerivedReview() throws {
        var state = PhoneState(); let current = try workout(at: date); try state.receive(current)
        #expect(state.localReview(for: current.id)?.matchedSets == 0)
        let older = try workout(at: date.addingTimeInterval(-600)); try state.receive(older)
        #expect(state.localReview(for: current.id)?.comparisons.first?.previousSessionID == older.id)
        #expect(state.sessions.first == current && state.review == nil && state.plan == nil)
    }
    @Test func repeatedVariationWithinWorkoutDoesNotGuessBaseline() throws {
        let prior = try workout(at: date.addingTimeInterval(-300))
        var a = ExercisePlan(name: "Warm-up row", sets: 1, reps: 10, weight: 10, restSeconds: 0)
        a.comparisonID = "row-a"; a.loadConvention = .machineStack
        var b = ExercisePlan(name: "Working row", sets: 1, reps: 10, weight: 20, restSeconds: 0)
        b.comparisonID = "row-a"; b.loadConvention = .machineStack
        var current = try WorkoutSession(plan: WorkoutPlan(title: "Repeated variation", exercises: [a,b]), now: date)
        try current.logSet(weight: 10, reps: 10, now: date.addingTimeInterval(10))
        try current.logSet(weight: 20, reps: 10, now: date.addingTimeInterval(20))
        #expect(WorkoutEvidenceReview(session: current, history: [prior]).matchedSets == 0)
    }
    @Test func cardioPausedIntervalsAndUnknownMeasurementsStayFactual() throws {
        var exercise = ExercisePlan(name: "Walk", sets: 1, reps: 1, weight: 0, restSeconds: 0)
        exercise.activity = ActivityPrescription(kind: .walking, durationSeconds: 900)
        var session = try WorkoutSession(plan: WorkoutPlan(title: "Walking", exercises: [exercise]), now: date)
        try session.startActivity(now: date)
        try session.pauseActivity(now: date.addingTimeInterval(20))
        try session.resumeActivity(now: date.addingTimeInterval(80))
        try session.completeActivity(now: date.addingTimeInterval(100))
        let review = WorkoutEvidenceReview(session: session, history: [])
        #expect(review.strengthSets == 0 && review.timedSegments == 1 && review.comparisons.isEmpty)
        #expect(review.session.activities?.first?.elapsedSeconds == 40 && review.session.activities?.first?.distanceMeters == nil)
    }
    @Test func expiredShortcutCannotApplyEvenWithoutForegroundRefresh() throws {
        var state = PhoneState(); let session = try workout(at: date); try state.receive(session)
        let ticket = try state.beginReview(now: date)
        let response = "{\"reviewSessionID\":\"\(ticket.sessionID)\",\"reviewAttemptID\":\"\(ticket.attemptID)\",\"analysis\":\"Feedback\",\"plan\":\(PlanImport.example)}"
        #expect(throws: (any Error).self) { try state.receiveReview(response, now: date.addingTimeInterval(600)) }
        #expect(state.review == nil && state.localReview(for: session.id) != nil)
        state.expireReviewAttempts(now: date.addingTimeInterval(601))
        #expect(state.reviewQueue.first?.status == .failed)
        let restored = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(state))
        #expect(restored.reviewQueue.first?.status == .failed && restored.sessions == state.sessions)
    }
    @Test func rhythmStopsWhenBackgroundSessionOrPreferenceIsLost() {
        #expect(RhythmEligibility.allows(appActive: false, workoutRunning: true, haptics: true, enabled: true, sameSet: true))
        #expect(!RhythmEligibility.allows(appActive: false, workoutRunning: false, haptics: true, enabled: true, sameSet: true))
        #expect(!RhythmEligibility.allows(appActive: true, workoutRunning: true, haptics: false, enabled: true, sameSet: true))
        #expect(!RhythmEligibility.allows(appActive: true, workoutRunning: true, haptics: true, enabled: false, sameSet: true))
        #expect(!RhythmEligibility.allows(appActive: true, workoutRunning: true, haptics: true, enabled: true, sameSet: false))
    }
    @Test func savedMachineSearchKeepsSeparateVariantsAndDeduplicatesToday() throws {
        var state = PhoneState(); let a = try workout(at: date, variation: "row-a").plan
        var b = try workout(at: date, variation: "row-b").plan
        b.exercises[0].name = "Remo sentado · máquina B"
        state.plan = a; state.routines = [Routine(plan: a), Routine(plan: b)]
        #expect(state.savedExercises(matching: "").count == 2)
        let matches = state.savedExercises(matching: "MAQUINA b")
        #expect(matches.count == 1 && matches.first?.exercise.comparisonID == "row-b")
    }
}
