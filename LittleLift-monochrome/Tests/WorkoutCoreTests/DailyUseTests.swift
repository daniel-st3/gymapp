import Foundation
import Testing
@testable import WorkoutCore

struct DailyUseTests {
    @Test func saveAndSendUsesOneExactRevisionAndPreservesScheduleHistory() throws {
        let original = try PlanImport.parse(PlanImport.example)
        var state = PhoneState(); try state.saveWorkout(original, useToday: true)
        let routine = try #require(state.routineLibrary.first)
        try state.scheduleRoutine(routine.id, weekday: 4)
        var session = try WorkoutSession(plan: original, now: Date(timeIntervalSince1970: 1000)); session.finish(now: Date(timeIntervalSince1970: 1060)); try state.receive(session)
        var edited = original; edited.exercises[0].weight += 5
        try state.saveWorkout(edited, replacing: routine.id, useToday: true)
        #expect(state.routineLibrary.count == 1)
        #expect(state.plan == state.routineLibrary[0].plan)
        #expect(state.plan?.id != original.id)
        #expect(state.routineLibrary[0].previousVersions == [original])
        #expect(state.weeklySchedule[0].routineID == routine.id)
        #expect(state.sessions == [session])
        let restored = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(state))
        #expect(restored == state)
        try state.saveWorkout(state.routineLibrary[0].plan, replacing: routine.id, useToday: true)
        #expect(state == restored) // Repeated Save is idempotent.
    }
    @Test func failedSaveIsAtomicAndMissingRoutineDoesNotCreateAnother() throws {
        var state = PhoneState(); let plan = try PlanImport.parse(PlanImport.example)
        try state.saveWorkout(plan, useToday: true); let before = state
        #expect(throws: (any Error).self) { try state.saveWorkout(plan, replacing: UUID(), useToday: true) }
        #expect(state == before)
        var invalid = plan; invalid.exercises[0].sets = 0
        #expect(throws: (any Error).self) { try state.saveWorkout(invalid, replacing: state.routineLibrary[0].id, useToday: true) }
        #expect(state == before)
    }
    @Test func libraryOnlySaveLeavesTodayAndChoosingDoesNotDuplicate() throws {
        var state = PhoneState(); let plan = try PlanImport.parse(PlanImport.example)
        try state.saveWorkout(plan, useToday: true)
        var changed = plan; changed.title = "New routine"
        try state.saveWorkout(changed, useToday: false)
        #expect(state.plan == plan)
        #expect(state.routineLibrary[1].plan.id != plan.id)
        let choice = state.routineLibrary[1].plan
        try state.saveWorkout(choice, useToday: true); try state.saveWorkout(choice, useToday: true)
        #expect(state.routineLibrary.count == 2)
        #expect(state.plan == choice)
    }
    @Test func confirmedDraftRemovalRemovesOnlyLinkedRequests() throws {
        var draft = try SmartWorkoutImport.extract(PlanImport.observationExample)
        let original = try #require(draft.original)
        let id = original.exercises[0].id
        draft.removeExercise(id)
        #expect(!draft.exercises.contains(where: { $0.id == id }))
        #expect(draft.original?.observations == original.observations?.filter { $0.exerciseID != id })
        #expect(!original.observationRequests.isEmpty) // The saved original is unchanged.
    }
    @Test func lastResultUsesActualSubstitutionAndNeverNameOnlyOrDifferentUnits() throws {
        var base = ExercisePlan(name: "Row", sets: 1, reps: 10, weight: 30, restSeconds: 0, comparisonID: "row-a", loadConvention: .machineStack)
        let alternative = ExerciseAlternative(name: "Row", comparisonID: "row-b", loadConvention: .machineStack, unit: .kg, reps: 8, weight: 20, restSeconds: 0)
        base.alternatives = [alternative]
        let plan = WorkoutPlan(title: "Rows", exercises: [base])
        let start = Date(timeIntervalSince1970: 1000)
        var old = try WorkoutSession(plan: plan, now: start)
        try old.substituteCurrent(with: alternative.id, now: start)
        try old.logSet(weight: 21, reps: 7, now: start.addingTimeInterval(20))
        #expect(Progression.lastResult(for: base, unit: .kg, sessions: [old]) == nil)
        let actual = alternative.exercise(sets: 1)
        #expect(Progression.lastResult(for: actual, unit: .kg, sessions: [old])?.entry.weight == 21)
        #expect(Progression.lastResult(for: actual, unit: .lb, sessions: [old]) == nil)
        var otherConvention = actual; otherConvention.loadConvention = .total
        #expect(Progression.lastResult(for: otherConvention, unit: .kg, sessions: [old]) == nil)
        var unknown = actual; unknown.comparisonID = nil; unknown.loadConvention = nil
        #expect(Progression.lastResult(for: unknown, unit: .kg, sessions: [old]) == nil)
        var latest = try WorkoutSession(plan: plan, now: start.addingTimeInterval(100))
        try latest.substituteCurrent(with: alternative.id, now: start.addingTimeInterval(100))
        try latest.logSet(weight: 22, reps: 8, now: start.addingTimeInterval(120))
        #expect(Progression.summary([latest, old]).contains("21 × 7 → 22 × 8"))
        #expect(Progression.lastResult(for: actual, unit: .kg, sessions: [old, latest])?.session.id == latest.id)
    }
    @Test func lastResultSkipsUnloggedAndActiveWorkouts() throws {
        let exercise = ExercisePlan(name: "Press", sets: 2, reps: 8, weight: 20, restSeconds: 0, comparisonID: "press-a", loadConvention: .total)
        let plan = WorkoutPlan(title: "Press", exercises: [exercise])
        var empty = try WorkoutSession(plan: plan); empty.finish()
        var active = try WorkoutSession(plan: plan); try active.logSet(weight: 20, reps: 7)
        #expect(Progression.lastResult(for: exercise, unit: .kg, sessions: [empty, active]) == nil)
    }
}
