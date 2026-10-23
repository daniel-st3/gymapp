import Foundation
import Testing
@testable import WorkoutCore

struct LibraryTests {
    @Test func textExtractionPreservesTargetsAndMissingInformation() throws {
        let draft = try SmartWorkoutImport.extract("Workout: Upper\nBench press — 3 x 8 @ 40 kg, rest 90 sec\nRow — 2 x 10 @ 30 kg")
        #expect(draft.title == "Upper")
        #expect(draft.exercises[0].name == "Bench press")
        #expect(draft.exercises[0].weight == "40")
        #expect(draft.exercises[0].rest == "90")
        #expect(draft.exercises[1].rest.isEmpty)
        #expect(throws: (any Error).self) { try draft.validated() }
        var fixed = draft; fixed.exercises[1].rest = "60"
        #expect(try fixed.validated().totalSets == 5)
    }
    @Test func modelUnitSuffixesNormalizeWithoutResolvingRangesOrNegativeWeights() throws {
        #expect(SmartWorkoutImport.cleanExtractedNumber("60 sec", kind: "rest") == "60")
        #expect(SmartWorkoutImport.cleanExtractedNumber("2 minutes", kind: "rest") == "120")
        #expect(SmartWorkoutImport.cleanExtractedNumber("3 sets", kind: "sets") == "3")
        #expect(SmartWorkoutImport.cleanExtractedNumber("8–12", kind: "reps") == "8–12")
        let draft = try SmartWorkoutImport.extract("Workout: Test\nRow 2 x 8 @ -20 kg rest 60 s")
        #expect(draft.exercises[0].weight == "-20") // retain invalid source for correction, never silently omit it
        #expect(draft.exercises[0].fieldsToReview.contains("Load"))
    }
    @Test func rangesAndMixedUnitsRequireExplicitResolution() throws {
        let range = try SmartWorkoutImport.extract("Workout: Test\nRow 3 x 8–12 @ 20 kg rest 1 min")
        #expect(range.exercises[0].reps.isEmpty)
        #expect(range.exercises[0].rest == "60")
        let mixed = try SmartWorkoutImport.extract("Workout: Test\nRow 2 x 10 @ 20 kg rest 60 s\nPress 2 x 8 @ 30 lb rest 90 s")
        #expect(throws: (any Error).self) { try mixed.validated() }
    }
    @Test func jsonDraftRetainsObservationReferencesDuringEditing() throws {
        var draft = try SmartWorkoutImport.extract(PlanImport.observationExample)
        let ids = draft.original?.observations
        draft.exercises[0].weight = "4.5"
        let plan = try draft.validated()
        #expect(plan.observations == ids)
        #expect(plan.exercises[0].weight == 4.5)
        draft.exercises[0].sets = "1"
        #expect(throws: (any Error).self) { try draft.validated() }
    }
    @Test func libraryRevisionsAndSchedulePreserveOriginalRecords() throws {
        var state = PhoneState(); let plan = try PlanImport.parse(PlanImport.example)
        state.plan = plan; try state.saveRoutine(plan)
        let id = try #require(state.routines?.first?.id)
        try state.scheduleRoutine(id, weekday: 2)
        var updated = plan; updated.exercises[0].weight = 45
        try state.saveRoutine(updated, replacing: id)
        #expect(state.routines?.first?.previousVersions == [plan])
        #expect(state.plan == plan)
        #expect(state.weeklySchedule.first?.routineID == id)
        let restored = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(state))
        #expect(restored == state)
        #expect(throws: (any Error).self) { try state.scheduleRoutine(UUID(), weekday: 2) }
    }
    @Test func importedHistoryIsDistinctDeduplicatedAndImmutable() throws {
        let records = try HistoryImport.parse(HistoryImport.example)
        var state = PhoneState(); try state.importHistory(records); try state.importHistory(records)
        #expect(state.sessions.isEmpty)
        #expect(state.externalHistory.count == 1)
        #expect(state.contextExport().contains("not measured by Little Lift"))
        #expect(state.contextExport().contains("No Little Lift timestamps"))
        let conflicting = try HistoryImport.parse(HistoryImport.example.replacingOccurrences(of: "\"weight\":30", with: "\"weight\":40"))
        #expect(throws: (any Error).self) { try state.importHistory(conflicting) }
        #expect(state.externalHistory == records)
    }
    @Test func historicalTargetsWithoutActualsAreRejected() {
        #expect(throws: (any Error).self) { try HistoryImport.parse(PlanImport.example) }
        #expect(throws: (any Error).self) { try HistoryImport.parse(HistoryImport.example.replacingOccurrences(of: "\"reps\":10", with: "\"reps\":0")) }
    }
    @Test func legacyPhoneStateDecodesNewOptionalFieldsAsAbsent() throws {
        let old = #"{"sessions":[],"profile":"Preferences preserved","mode":"existingChat"}"#
        let state = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: Data(old.utf8))
        #expect(state.routines == nil && state.schedule == nil && state.importedHistory == nil)
        #expect(state.profile == "Preferences preserved")
    }
    @Test func approvalMetadataAndAlternativeValidationRoundTrip() throws {
        var plan = try PlanImport.parse(PlanImport.observationExample)
        plan.exercises[0].workPolicy = WorkPolicy(priority: 2, optional: true)
        plan.exercises[0].alternatives = [ExerciseAlternative(name: "Machine press", comparisonID: "machine-press-a", loadConvention: .machineStack, unit: .kg, reps: 8, weight: 20, restSeconds: 90)]
        let data = try FileRepository<WorkoutPlan>.encoder().encode(plan)
        let decoded = try PlanImport.parse(String(decoding: data, as: UTF8.self))
        #expect(decoded.exercises == plan.exercises)
        plan.exercises[0].workPolicy?.priority = 0
        #expect(throws: (any Error).self) { try plan.validate() }
    }
    @Test func legacyDraftDoesNotInventApprovalMetadataAndExplicitConventionIsRetained() throws {
        let plan = try PlanImport.parse(PlanImport.example)
        #expect(try WorkoutDraft(plan: plan).validated() == plan)
        let draft = try SmartWorkoutImport.extract("Workout: Test\nCurl 3 x 8 @ 5 kg per dumbbell rest 60 sec")
        #expect(draft.exercises[0].convention == "perDumbbell")
        #expect(draft.exercises[0].comparisonID.isEmpty)
        #expect(try draft.validated().exercises[0].comparisonID == nil)
        #expect(try draft.validated().schemaVersion == 3)
        #expect(SmartWorkoutImport.explicitConvention(in: "per dumbbell or total load unclear").isEmpty)
    }

}
