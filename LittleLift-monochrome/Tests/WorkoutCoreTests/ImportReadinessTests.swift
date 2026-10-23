import Foundation
import Testing
@testable import WorkoutCore

struct ImportReadinessTests {
    @Test func pluralPoundsAndDecimalLoadsAreNeverDropped() throws {
        for unit in ["lb", "lbs", "LB", "LBS", "pounds", "libras"] {
            let draft = try SmartWorkoutImport.extract("Workout: Pierna\nPrensa — 2 x 10 — 80,5 \(unit) — rest 90 s")
            #expect(draft.reviewIssues.isEmpty)
            let plan = try draft.validated()
            #expect(plan.unit == .lb && plan.exercises[0].weight == 80.5)
            #expect(plan.exercises[0].loadIsUnspecified != true)
        }
    }
    @Test func missingLoadAllowsExplicitWatchChoiceButMissingUnitsRemainVisible() throws {
        var draft = try SmartWorkoutImport.extract("Workout: Pierna\nPrensa 2 x 10 rest 90 s\nCurl 1 x 12 30 lbs rest 60 s")
        #expect(draft.exercises[0].chooseLoadOnWatch)
        #expect(draft.reviewIssues.count == 1)
        #expect(draft.reviewIssues[0].exerciseID == draft.exercises[0].id)
        #expect(draft.reviewIssues[0].message.contains("Unit"))
        #expect(!draft.reviewIssues[0].message.contains("Load"))
        draft.fillMissingUnit(.lb)
        #expect(draft.reviewIssues.isEmpty)
        let plan = try draft.validated()
        #expect(plan.exercises[0].loadIsUnspecified == true && plan.exercises[1].weight == 30)
    }
    @Test func partialJSONPreservesPoundsAndDoesNotHideUnitConflicts() throws {
        let text = #"{"title":"Pierna","exercises":[{"name":"Prensa","sets":2,"reps":10,"weight":"80 lbs","restSeconds":90}]}"#
        let draft = try SmartWorkoutImport.extract(text)
        #expect(try draft.validated().unit == .lb)
        #expect(try draft.validated().exercises[0].weight == 80)
        let conflict = text.replacingOccurrences(of: "{\"title\"", with: "{\"unit\":\"kg\",\"title\"")
        #expect(try SmartWorkoutImport.extract(conflict).exercises[0].unit.isEmpty)
    }
    @Test func labelledLoadWithoutUnitSurvivesUntilUserConfirmsUnit() throws {
        var draft = try SmartWorkoutImport.extract("Workout: Pierna\nPrensa 2 x 10 — peso: 80 — rest 90 s")
        #expect(draft.exercises[0].weight == "80" && draft.exercises[0].unit.isEmpty)
        #expect(!draft.exercises[0].chooseLoadOnWatch)
        draft.fillMissingUnit(.lb)
        #expect(try draft.validated().exercises[0].weight == 80)
    }
    @Test func ambiguousOCRUnitRetainsNumbersAndAsksOnlyForTheUnit() throws {
        var draft = try SmartWorkoutImport.extract("Workout: Pierna\nPrensa 2 x 10 — Peso: 80 Ibs — rest 90 s\nCurl 1 x 12 — 30 1bs — rest 60 s")
        #expect(draft.exercises.map(\.weight) == ["80", "30"])
        #expect(draft.exercises.allSatisfy { $0.unit.isEmpty && !$0.chooseLoadOnWatch })
        #expect(draft.reviewIssues.count == 2)
        draft.fillMissingUnit(.lb)
        #expect(try draft.validated().exercises.map(\.weight) == [80,30])
    }
    @Test func dateMetadataIsNotAnExtraExerciseOrHistoricalEvidence() throws {
        for source in [
            "Workout: Pierna\nDate: 2026-10-23\nPrensa 2 x 10 80 lbs rest 90 s",
            "Fecha: 23/10/2026\n**Entrenamiento: Pierna**\n1. Prensa\n2 x 10\nPeso: 80 lbs\nDescanso: 90 s",
            "2026-10-23\nWorkout: Pierna\nPrensa 2 x 10 80 lbs rest 90 s"
        ] {
            let draft = try SmartWorkoutImport.extract(source)
            #expect(draft.exercises.count == 1 && draft.source == source)
            let plan = try draft.validated()
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let session = try WorkoutSession(plan: plan, now: started)
            #expect(session.startedAt == started)
        }
    }
    @Test func everyInvalidExerciseIsListedAndRepairsClearReadiness() throws {
        var draft = try SmartWorkoutImport.extract("Workout: Pierna\nPrensa 2 x 8–12 80 lbs\nCurl 99 x 12 30 lbs rest 60 s")
        #expect(draft.reviewIssues.count == 2)
        #expect(draft.reviewIssues[0].message.contains("Repetitions"))
        #expect(draft.reviewIssues[0].message.contains("Rest"))
        #expect(draft.reviewIssues[1].message.contains("Sets"))
        draft.exercises[0].reps = "10"; try draft.fillMissingRest(90); draft.exercises[1].sets = "2"
        #expect(draft.reviewIssues.isEmpty)
        var phone = PhoneState(); let original = try PlanImport.parse(PlanImport.example); phone.plan = original
        try phone.saveWorkout(draft.validated(), useToday: true)
        #expect(phone.routineLibrary.contains { $0.plan == original })
        let restored = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(phone))
        #expect(restored == phone && restored.plan?.unit == .lb)
    }
    @Test func invalidAndMixedLoadsNeverBecomeInventedTargets() throws {
        for load in ["-20 lbs", "20–30 lbs", "1001 lbs"] {
            let draft = try SmartWorkoutImport.extract("Workout: Pierna\nPrensa 2 x 10 \(load) rest 90 s")
            #expect(!draft.exercises[0].chooseLoadOnWatch)
            #expect(!draft.reviewIssues.isEmpty)
            #expect(throws: WorkoutError.self) { try draft.validated() }
        }
        let mixed = try SmartWorkoutImport.extract("Workout: A\nPrensa 2 x 10 80 lbs rest 90 s\nCurl 1 x 12 20 kg rest 60 s")
        #expect(mixed.reviewIssues.count == 1 && mixed.reviewIssues[0].exerciseID == nil)
        #expect(mixed.reviewIssues[0].message.contains("Mixed units"))
        var title = try SmartWorkoutImport.extract("Workout: A\nPrensa 2 x 10 80 lbs rest 90 s")
        title.title = ""
        #expect(title.reviewIssues.first?.id == "title")
        title.title = "A"; title.exercises = []
        #expect(title.reviewIssues.first?.id == "workout")
    }
    @Test func chatMessageSuppliesLocalDateAcrossTimezoneBoundaryAndRequestsEveryLoad() throws {
        var state = PhoneState()
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-24T02:30:00Z"))
        let packet = try state.prepareChatHandoff(request: "", now: now)
        let prompt = packet.prompt(timeZone: try #require(TimeZone(identifier: "America/Bogota")))
        #expect(prompt.contains("TODAY: 2026-10-23 · America/Bogota"))
        #expect(prompt.contains("Include each confirmed load AND its unit"))
        #expect(prompt.contains("Never invent a target"))
        let legacy = try FileRepository<ChatHandoff>.decoder().decode(ChatHandoff.self, from: FileRepository<ChatHandoff>.encoder().encode(packet))
        #expect(legacy == packet)
    }
    @Test func copyingUnchangedContextOnAnotherDayRefreshesTheDatedRequest() throws {
        var state = PhoneState()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try state.prepareChatHandoff(request: "", now: day)
        #expect(try state.prepareChatHandoff(request: "", now: day).id == first.id)
        let nextDay = day.addingTimeInterval(86_400)
        let fresh = try state.prepareChatHandoff(request: "", now: nextDay)
        #expect(fresh.id != first.id && fresh.preparedAt == nextDay)
        #expect(fresh.context == first.context)
        #expect(throws: WorkoutError.self) { try state.validateChatReply(first.id) }
        try state.validateChatReply(fresh.id)
    }
}
