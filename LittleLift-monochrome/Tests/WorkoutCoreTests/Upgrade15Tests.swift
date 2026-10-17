import Foundation
import Testing
@testable import WorkoutCore

struct Upgrade15Tests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    func partial() throws -> WorkoutSession {
        var p = FlexibilityTests().plan(); p.exercises[0].sets = 3
        p.observations = [ObservationRequest(id: "original", kind: .performance, exerciseID: p.exercises[0].id)]
        var s = try WorkoutSession(plan: p, now: start)
        try s.logSet(weight: 21, reps: 9, now: start.addingTimeInterval(10), uptime: 100)
        return s
    }
    @Test func partialSwitchPreservesOriginalRestTargetsAndIndependentHistory() throws {
        var s = try partial(); let before = s; let alt = s.plan.exercises[0].alternatives![0]
        try s.substituteCurrent(with: alt.id, now: start.addingTimeInterval(12))
        #expect(s.entries == before.entries && s.plan == before.plan && s.restUntil == before.restUntil)
        #expect(s.currentExercise?.id == alt.id && s.currentExercise?.sets == 2 && s.currentSetNumber == 1)
        #expect(s.completedExerciseCount == 0)
        s = try FileRepository<WorkoutSession>.decoder().decode(WorkoutSession.self, from: FileRepository<WorkoutSession>.encoder().encode(s))
        s.skipRest(now: start.addingTimeInterval(70))
        try s.logSet(weight: 15, reps: 8, now: start.addingTimeInterval(80), uptime: 170)
        #expect(s.entries[1].exerciseID == alt.id && s.entries[1].setNumber == 1)
        #expect(s.loggingInterval(before: s.entries[1]) == nil)
        #expect(!s.canSubstitute(with: alt))
        s.skipRest(now: start.addingTimeInterval(170))
        try s.logSet(weight: 15, reps: 7, now: start.addingTimeInterval(180), uptime: 270)
        #expect(s.completedExerciseCount == 1)
        s.finish(now: start.addingTimeInterval(181)); try s.validateCompleted()
        #expect(s.observationEvidence.filter { $0.setID != nil }.count == 1)
        #expect(s.report().contains("Row A") && s.report().contains("Row B"))
        var phone = PhoneState(); try phone.receive(s); try phone.receive(s)
        #expect(phone.sessions == [s])
        #expect(TrainingAnalytics(state: phone, now: start.addingTimeInterval(200)).exercises.count == 2)
        let restored = try WorkoutBackup.decode(WorkoutBackup(state: phone).encoded())
        #expect(restored.state.sessions == [s])
    }
    @Test func partialSwitchUndoBeforeAndAfterAlternateLogKeepsAllReferencesValid() throws {
        var s = try partial(); let alt = s.plan.exercises[0].alternatives![0]
        try s.substituteCurrent(with: alt.id, now: start.addingTimeInterval(12))
        try s.undoAdjustment(now: start.addingTimeInterval(13))
        #expect(s.currentExercise?.name == "Row A" && s.currentSetNumber == 2)
        try s.substituteCurrent(with: alt.id, now: start.addingTimeInterval(14))
        s.skipRest(now: start.addingTimeInterval(70))
        try s.logSet(weight: 15, reps: 8, now: start.addingTimeInterval(80), uptime: 170)
        try s.undoLastSet(); try s.validateExecution()
        #expect(s.entries.count == 1 && s.currentExercise?.id == alt.id)
        try s.undoLastSet(); try s.validateExecution()
        #expect(s.entries.isEmpty && s.currentExercise?.name == "Row A" && s.execution.substitutions.isEmpty)
    }
    @Test func forgedPartialSwitchCannotHideOrReassignOriginalSets() throws {
        var s = try partial(); let alt = s.plan.exercises[0].alternatives![0]
        try s.substituteCurrent(with: alt.id, now: start.addingTimeInterval(12)); s.finish(now: start.addingTimeInterval(13))
        var json = try JSONSerialization.jsonObject(with: FileRepository<WorkoutSession>.encoder().encode(s)) as! [String: Any]
        var config = json["configuration"] as! [String: Any]
        var substitutions = config["substitutions"] as! [[String: Any]]
        for invalid in [Int.min, -1, 0, 2, 3, Int.max] {
            substitutions[0]["retainedSets"] = invalid; config["substitutions"] = substitutions; json["configuration"] = config
            let bad = try FileRepository<WorkoutSession>.decoder().decode(WorkoutSession.self, from: JSONSerialization.data(withJSONObject: json))
            #expect(throws: (any Error).self) { try bad.validateCompleted() }
        }
    }
    @Test func tableImportPreservesColumnsDecimalUnitsAndUnresolvedRanges() throws {
        var draft = try SmartWorkoutImport.extract("Entrenamiento: A\n| Ejercicio | Series | Reps | Peso (kg) | Descanso (s) |\n|---|---|---|---|---|\n| Remo | 3 | 8 | 20,5 | 90 |\n| Press | 2 | 8–12 | 15 | |").self
        #expect(draft.title == "A" && draft.exercises.count == 2)
        #expect(draft.exercises[0].weight == "20,5" && draft.exercises[0].unit == "kg")
        #expect(draft.exercises[1].fieldsToReview.contains("Repetitions") && draft.exercises[1].fieldsToReview.contains("Rest · seconds"))
        #expect(throws: (any Error).self) { try draft.validated() }
        draft.exercises[1].reps = "10"; draft.exercises[1].rest = "60"
        #expect(try draft.validated().exercises[0].weight == 20.5)
    }
    @Test func ambiguousHeadingsAndRowsCannotInventValues() throws {
        let mismatched = try SmartWorkoutImport.extract("Exercise\tSets\tReps\tWeight\tRest\nRow\t3\t10\t20\t90\nPress\t2\t8")
        #expect(mismatched.exercises[0].unit.isEmpty && mismatched.exercises[0].rest.isEmpty)
        #expect(mismatched.exercises[1].sets.isEmpty)
        let conflict = try SmartWorkoutImport.extract("Exercise|Sets|Reps|Weight (kg)|Unit|Rest (s)\nRow|2|8|20|lb|60")
        #expect(conflict.exercises[0].unit.isEmpty)
        #expect(throws: (any Error).self) { try conflict.validated() }
    }
    @Test func multilineSpanishRangesAndExtremeRestAreConservative() throws {
        let d = try SmartWorkoutImport.extract("Entrenamiento: A\nRemo 3 series de 8 @ 20–25 kg\nDescanso: 90 segundos")
        #expect(d.exercises.count == 1 && d.exercises[0].rest == "90" && d.exercises[0].reps == "8")
        #expect(d.exercises[0].fieldsToReview.contains("Load"))
        #expect(throws: (any Error).self) { try d.validated() }
        let huge = try SmartWorkoutImport.extract("Workout: A\nRow 3 x 8 20 kg rest 9223372036854775807 min")
        #expect(huge.exercises[0].rest.isEmpty)
        #expect(SmartWorkoutImport.cleanExtractedNumber("9223372036854775807 min", kind: "rest").contains("min"))
    }
    @Test func ocrRowsPreserveExplicitTableHeadings() throws {
        let boxes = [OCRTextBox(text: "Reps", x: 0.8, y: 0.9, height: 0.02), OCRTextBox(text: "Exercise", x: 0.1, y: 0.9, height: 0.02), OCRTextBox(text: "Sets", x: 0.6, y: 0.9, height: 0.02), OCRTextBox(text: "8", x: 0.8, y: 0.8, height: 0.02), OCRTextBox(text: "Row", x: 0.1, y: 0.8, height: 0.02), OCRTextBox(text: "3", x: 0.6, y: 0.8, height: 0.02)]
        let text = try OCRReadingOrder.text(from: boxes)
        #expect(text == "Exercise\tSets\tReps\nRow\t3\t8")
        let draft = try SmartWorkoutImport.extract(text)
        #expect(draft.exercises[0].sets == "3" && draft.exercises[0].weight.isEmpty)
    }
    @Test func duplicateEscapedJSONKeysAndDeepPayloadsAreRejectedAcrossBoundaries() throws {
        for value in [#"{"a":1,"\u0061":2}"#, #"{"a":{"b":1,"b":2}}"#, String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33)] {
            #expect(throws: (any Error).self) { try JSONBoundary.validate(Data(value.utf8)) }
        }
        try JSONBoundary.validate(Data(#"{"a":[{"b":1},{"b":2}],"text":"escaped \" quote"}"#.utf8))
        let plan = PlanImport.example.replacingOccurrences(of: "\"weight\": 40", with: "\"weight\": 1, \"weight\": 40")
        #expect(throws: (any Error).self) { try PlanImport.parse(plan) }
        let q = ReviewQueueTests(); var state = PhoneState(); try state.receive(q.completed())
        let ticket = try state.beginReview(now: q.now)
        #expect(throws: (any Error).self) { try PlanImport.parse(q.response(ticket)) }
        let before = state
        #expect(throws: (any Error).self) { try state.receiveReview(q.response(ticket), now: q.now.addingTimeInterval(-1)) }
        #expect(state == before)
    }

    @Test func connectionCheckIsIsolatedDurableBoundedAndReplaySafe() throws {
        var phone = PhoneState(); phone.plan = try PlanImport.parse(PlanImport.example); phone.profile = "PRIVATE PROFILE"
        let original = phone
        let prompt = try phone.beginConnectionCheck(now: start)
        #expect(!prompt.contains("PRIVATE PROFILE") && !prompt.contains(phone.plan!.title))
        let id = phone.coachConnectionCheck!.id
        #expect(throws: WorkoutError.self) { try phone.beginConnectionCheck(now: start.addingTimeInterval(1)) }
        phone = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(phone))
        let response = "{\"connectionCheckID\":\"\(id)\",\"confirmedRepetitions\":8}"
        let pending = phone
        #expect(throws: WorkoutError.self) { try phone.receiveConnectionCheck(response, now: start.addingTimeInterval(-1)) }
        #expect(throws: WorkoutError.self) { try phone.receiveConnectionCheck(response.replacingOccurrences(of: ":8", with: ":10"), now: start.addingTimeInterval(1)) }
        #expect(phone == pending)
        #expect(try phone.receiveConnectionCheck(response, now: start.addingTimeInterval(2)))
        let received = phone
        #expect(try phone.receiveConnectionCheck(response, now: start.addingTimeInterval(3)))
        #expect(phone == received)
        phone.coachConnectionCheck = nil; #expect(phone == original)
        _ = try phone.beginConnectionCheck(now: start); let current = phone.coachConnectionCheck!.id
        let stale = response.replacingOccurrences(of: id.uuidString, with: current.uuidString)
        phone.cancelConnectionCheck()
        #expect(throws: WorkoutError.self) { try phone.receiveConnectionCheck(stale, now: start.addingTimeInterval(2)) }
        _ = try phone.beginConnectionCheck(now: start.addingTimeInterval(3))
        #expect(throws: WorkoutError.self) { try phone.receiveConnectionCheck(stale, now: start.addingTimeInterval(4)) }
        let latest = stale.replacingOccurrences(of: current.uuidString, with: phone.coachConnectionCheck!.id.uuidString)
        #expect(throws: WorkoutError.self) { try phone.receiveConnectionCheck(latest, now: start.addingTimeInterval(603)) }
    }
    @Test func fileRoutingAndMixedCardioUnitsStayUnambiguous() throws {
        #expect(throws: WorkoutError.self) { try WorkoutFileImport.text(from: Data("{\"plan\":{},\"plan\":{}}".utf8)) }
        #expect(throws: WorkoutError.self) { try WorkoutFileImport.text(from: Data(repeating: 65, count: 64_001)) }
        let draft = try SmartWorkoutImport.extract("Workout: Walk\nWalking 15 min at 3 mph, distance 2 km")
        #expect(draft.exercises[0].speed.isEmpty && draft.exercises[0].distance.isEmpty)
        #expect(draft.notes.contains(where: { $0.contains("different units") }))
    }

    @Test func missingOCRCellsAndSpacedSetRangesCannotShiftTargets() throws {
        let boxes = [OCRTextBox(text:"Exercise",x:0.05,y:0.9,height:0.04), OCRTextBox(text:"Sets",x:0.4,y:0.9,height:0.04), OCRTextBox(text:"Reps",x:0.65,y:0.9,height:0.04), OCRTextBox(text:"Row",x:0.05,y:0.7,height:0.04), OCRTextBox(text:"10",x:0.65,y:0.7,height:0.04)]
        let draft = try SmartWorkoutImport.extract(OCRReadingOrder.text(from:boxes))
        #expect(draft.exercises[0].name == "Row" && draft.exercises[0].sets.isEmpty && draft.exercises[0].reps == "10")
        let range = try SmartWorkoutImport.extract("Workout: Range\nRow 3 - 4 x 8 @ 20 kg rest 60s")
        #expect(range.exercises[0].sets.isEmpty && range.exercises[0].reps == "8" && range.exercises[0].name == "Row")
    }
}
