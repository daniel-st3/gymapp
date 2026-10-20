import Foundation
import Testing
@testable import WorkoutCore

struct WorkoutPasteTests {
    let text = "Workout: Pierna\nPrensa — 2 x 10 — 40 kg — rest 90 s\nCurl femoral sentado — 1 x 12 — 20 kg — rest 90 s"

    @Test func ordinaryTextCodeBlocksOpenAsWorkoutsNotJSON() throws {
        for language in ["", "text", "plaintext", "markdown"] {
            let pasted = "Aquí está tu entrenamiento:\n```\(language)\n\(text)\n```\nRevísalo antes de entrenar."
            #expect(try ChatWorkoutReply.parseIfPresent(pasted) == nil)
            let draft = try SmartWorkoutImport.extract(pasted)
            let plan = try draft.validated()
            #expect(plan.title == "Pierna" && plan.exercises.count == 2)
            #expect(plan.exercises[0].weight == 40 && plan.exercises[0].restSeconds == 90)
            #expect(draft.source == pasted)
        }
    }

    @Test func singleJSONBlockWithCommentaryAndLegacyRepliesRemainSupported() throws {
        let pasted = "Claro:\n```json\n\(PlanImport.example)\n```\nListo."
        #expect(try SmartWorkoutImport.extract(pasted).validated().exercises.count == 3)
        var state = PhoneState()
        let packet = try state.prepareChatHandoff(request: "")
        let reply = "Aquí está:\n```json\n{\"handoffID\":\"\(packet.id)\",\"analysis\":\"Pierna acordada\",\"plan\":\(PlanImport.example)}\n```"
        let decoded = try #require(try ChatWorkoutReply.parseIfPresent(reply))
        try state.validateChatReply(decoded.handoffID)
        #expect(throws: WorkoutError.self) { try SmartWorkoutImport.extract(reply) }
    }

    @Test func incompleteOrdinaryJSONKeepsValuesAndNeedsExplicitDecisions() throws {
        let json = #"{"title":"Pierna","exercises":[{"name":"Prensa","sets":"3","reps":"8-12"},{"name":"Curl","sets":2,"reps":12,"weight":"20,5","restSeconds":"90 s"}]}"#
        var draft = try SmartWorkoutImport.extract(json)
        #expect(draft.exercises.count == 2)
        #expect(draft.exercises[0].reps == "8-12" && draft.exercises[0].chooseLoadOnWatch)
        #expect(draft.exercises[0].rest.isEmpty && draft.exercises[0].unit.isEmpty)
        #expect(draft.exercises[1].weight == "20,5" && draft.exercises[1].rest == "90")
        #expect(throws: WorkoutError.self) { try draft.validated() }
        draft.fillMissingUnit(.kg); try draft.fillMissingRest(120); draft.exercises[0].reps = "10"
        let plan = try draft.validated()
        #expect(plan.exercises[0].loadIsUnspecified == true && plan.exercises[0].restSeconds == 120)
        #expect(plan.exercises[1].weight == 20.5 && plan.exercises[1].restSeconds == 90)
    }

    @Test func partialJSONNeverDropsUnsupportedObservationOrCorrelation() throws {
        let partial = #"{"title":"Pierna","unit":"kg","exercises":[{"name":"Prensa","sets":3,"reps":10}]}"#
        for extra in [#""observations":[{"kind":"actualRest"}],"#, #""timeBudget":{"durationMinutes":30},"#] {
            let json = "{" + extra + partial.dropFirst()
            #expect(throws: WorkoutError.self) { try SmartWorkoutImport.extract(json) }
        }
        for key in ["handoffID", "reviewSessionID", "reviewAttemptID", "connectionCheckID"] {
            let json = "{\"" + key + "\":\"" + UUID().uuidString + "\"," + partial.dropFirst()
            #expect(throws: WorkoutError.self) { try SmartWorkoutImport.extract(json) }
        }
    }

    @Test func malformedBoundedAndAmbiguousInputIsNotGuessed() throws {
        for value in [
            "```text\n\(text)",
            "```text\n\(text)\n```\n```text\nOther\n```",
            #"{"title":"A","title":"B","exercises":[]}"#,
            String(repeating: "x", count: 64_001)
        ] {
            #expect(throws: WorkoutError.self) { try SmartWorkoutImport.extract(value) }
        }
        let json = #"{"title":"Pierna","unit":"kg","exercises":[{"name":"Prensa","sets":999,"reps":10,"weight":40,"restSeconds":90}]}"#
        let draft = try SmartWorkoutImport.extract(json)
        #expect(draft.exercises[0].sets == "999")
        #expect(throws: WorkoutError.self) { try draft.validated() }
    }

    @Test func newEverydayPromptRequestsTextAndOldHistoryStaysUntouched() throws {
        var state = PhoneState(); state.plan = try PlanImport.parse(PlanImport.example)
        let original = state.plan
        let packet = try state.prepareChatHandoff(request: "Hoy pierna", now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(packet.prompt.contains("Use ordinary text, not JSON"))
        let draft = try SmartWorkoutImport.extract(text)
        #expect(state.plan == original)
        try state.saveWorkout(draft.validated(), useToday: true)
        #expect(state.plan?.title == "Pierna" && state.routineLibrary.contains { $0.plan == original })
        let restored = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(state))
        #expect(restored == state)
    }

    @Test func appLinksOnlyUseOfficialPrivateConversationRoutes() throws {
        #expect(try ChatAppLink.destination("").absoluteString == "https://chatgpt.com/open-app")
        let id = UUID().uuidString
        #expect(try ChatAppLink.destination("https://chat.openai.com/c/\(id)").absoluteString == "https://chatgpt.com/c/\(id.lowercased())")
        for url in [
            "https://chatgpt.com/share/\(id)", "https://example.com/c/\(id)",
            "https://chatgpt.com@evil.com/c/\(id)", "javascript:alert(1)",
            "https://chatgpt.com/c/\(id)?no_universal_links=1",
            "https://chatgpt.com/c/\(id)#no_universal_links",
            "https://chatgpt.com/c/../open-app", "http://chatgpt.com/c/\(id)"
        ] { #expect(throws: WorkoutError.self) { try ChatAppLink.destination(url) } }
    }
}
