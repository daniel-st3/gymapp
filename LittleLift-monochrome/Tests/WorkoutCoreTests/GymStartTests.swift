import Foundation
import Testing
@testable import WorkoutCore

struct GymStartTests {
    let message = """
    ## Pierna
    Hoy puedes hacer esta sesión.
    1. **Prensa de piernas**
    3 series de 10–12 repeticiones
    Descanso: 90 segundos
    2. **Curl femoral sentado**
    3 x 12
    Descanso: 60 segundos
    Mantén el movimiento controlado.
    """
    @Test func ordinaryChatGroupsNamesTargetsAndIgnoresCommentary() throws {
        let draft = try SmartWorkoutImport.extract(message)
        #expect(draft.title == "Pierna")
        #expect(draft.exercises.map(\.name) == ["Prensa de piernas", "Curl femoral sentado"])
        #expect(draft.exercises.map(\.sets) == ["3", "3"])
        #expect(draft.exercises[0].reps.isEmpty)
        #expect(draft.exercises[0].repetitionChoices == [10, 12])
        #expect(draft.exercises.map(\.rest) == ["90", "60"])
        #expect(draft.exercises.allSatisfy { $0.weight.isEmpty && $0.unit.isEmpty })
        #expect(draft.source == message)
    }
    @Test func labelledBlocksAndDecimalLoadsKeepTheirMeaning() throws {
        let draft = try SmartWorkoutImport.extract("Rutina: Pierna\n1. Prensa\nSeries: 3\nRepeticiones: 10\nPeso: 20,5 kg\nDescanso: 90 s\n2. Curl femoral 2 x 12 15 kg descanso 60 s")
        #expect(draft.exercises.map(\.name) == ["Prensa", "Curl femoral"])
        #expect(draft.exercises[0].weight == "20,5")
        #expect(try draft.validated().totalSets == 5)
    }
    @Test func missingTargetsAreExplicitChoicesAndNeverOverwritePrescriptions() throws {
        var draft = try SmartWorkoutImport.extract("Pierna\nPrensa 3 x 10\nCurl 2 x 12 10 kg descanso 90 s")
        #expect(throws: WorkoutError.self) { try draft.validated() }
        draft.exercises[0].chooseLoadOnWatch = true
        draft.fillMissingUnit(.kg); try draft.fillMissingRest(60)
        let plan = try draft.validated()
        #expect(plan.schemaVersion == 3 && plan.exercises[0].loadIsUnspecified == true)
        #expect(plan.exercises[1].weight == 10 && plan.exercises[1].restSeconds == 90)
        #expect(try WorkoutDraft(plan: plan).validated() == plan)
        #expect(throws: WorkoutError.self) { try draft.fillMissingRest(Int.max) }
    }
    @Test func unspecifiedLoadSurvivesImportDeliveryUndoAndReportsWithoutZeroTarget() throws {
        var exercise = ExercisePlan(name: "Leg press", sets: 2, reps: 10, weight: 0, restSeconds: 60)
        exercise.loadIsUnspecified = true
        var plan = WorkoutPlan(title: "Leg day", exercises: [exercise]); plan.schemaVersion = 3
        plan.observationSchemaVersion = 1
        plan.observations = [ObservationRequest(id: "check-load", kind: .performance, exerciseID: exercise.id)]
        let data = try FileRepository<WorkoutPlan>.encoder().encode(plan)
        #expect(try PlanImport.parse(String(decoding: data, as: UTF8.self)) == plan)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var session = try WorkoutSession(plan: plan, now: now)
        try session.logSet(weight: 30, reps: 9, now: now.addingTimeInterval(10), uptime: 100)
        #expect(session.observationEvidence[0].detail.contains("Load not prescribed"))
        #expect(!session.observationEvidence[0].detail.contains("Difference: 30"))
        try session.undoLastSet(); #expect(session.entries.isEmpty)
        try session.logSet(weight: 35, reps: 10, now: now.addingTimeInterval(20), uptime: 110)
        session.finish(now: now.addingTimeInterval(21))
        #expect(session.report().contains("choose load on Watch"))
        var phone = PhoneState(); try phone.receive(session); try phone.receive(session)
        #expect(phone.sessions.count == 1)
        let restored = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(phone))
        #expect(restored == phone && restored.sessions[0].entries[0].weight == 35)
    }
    @Test func invalidAndLegacyTargetsStayProtected() throws {
        let legacy = try PlanImport.parse(PlanImport.example)
        #expect(legacy.exercises.allSatisfy { $0.loadIsUnspecified == nil })
        var plan = legacy; plan.exercises[0].loadIsUnspecified = true
        #expect(throws: WorkoutError.self) { try plan.validate() }
        plan.schemaVersion = 3
        #expect(throws: WorkoutError.self) { try plan.validate() } // cannot hide numeric prescription
        plan.exercises[0].weight = 0; try plan.validate()
        plan.exercises[0].loadConvention = .bodyweight
        #expect(throws: WorkoutError.self) { try plan.validate() }
    }
    @Test func conventionDoesNotForceInventingComparisonIdentity() throws {
        var draft = try SmartWorkoutImport.extract("Workout: Leg\nSplit squat 2 x 8 10 kg per dumbbell rest 60 s")
        let plan = try draft.validated()
        #expect(plan.schemaVersion == 3 && plan.exercises[0].loadConvention == .perDumbbell)
        #expect(plan.exercises[0].comparisonID == nil)
        #expect(!plan.exercises[0].matches(plan.exercises[0], unit: .kg, otherUnit: .kg))
        draft.exercises[0].comparisonID = "same-exact-variation"
        #expect(try draft.validated().exercises[0].comparisonID != nil)
    }
    @Test func importingTodayArchivesAnOlderPlanWithoutInventingWorkoutHistory() throws {
        var state = PhoneState(); let old = try PlanImport.parse(PlanImport.example); state.plan = old
        var new = old; new.id = UUID(); new.title = "Leg day"
        try state.saveWorkout(new, useToday: true)
        #expect(state.plan == new && state.sessions.isEmpty)
        #expect(state.routineLibrary.contains { $0.plan == old })
        #expect(state.routineLibrary.contains { $0.plan == new })
        try state.saveWorkout(new, useToday: true); #expect(state.routineLibrary.count == 2)
    }
    @Test func newPlanRequiresExplicitWatchSwitchAndPreservesRecordedWork() throws {
        let old = try PlanImport.parse(PlanImport.example)
        var new = old; new.id = UUID(); new.title = "Leg day"
        var watch = WatchState(); watch.plan = new; watch.session = try WorkoutSession(plan: old)
        #expect(watch.canReplaceUnloggedWorkout && watch.session?.plan == old)
        let roundtrip = try FileRepository<WatchState>.decoder().decode(WatchState.self, from: FileRepository<WatchState>.encoder().encode(watch))
        #expect(roundtrip.canReplaceUnloggedWorkout)
        try watch.replaceUnloggedWorkout(); #expect(watch.session?.plan == new)
        try watch.session?.logSet(weight: 20, reps: 8)
        watch.plan = old
        let original = watch
        #expect(!watch.canReplaceUnloggedWorkout)
        #expect(throws: WorkoutError.self) { try watch.replaceUnloggedWorkout() }
        #expect(watch == original)
    }
}
