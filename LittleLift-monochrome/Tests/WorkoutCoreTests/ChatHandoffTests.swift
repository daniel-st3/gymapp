import Foundation
import Testing
@testable import WorkoutCore

struct ChatHandoffTests {
    func reply(_ packet: ChatHandoff, plan: WorkoutPlan) throws -> ChatWorkoutReply {
        let data = try JSONEncoder().encode(plan)
        let json = "{\"handoffID\":\"\(packet.id)\",\"analysis\":\"Agreed workout\",\"plan\":\(String(decoding: data, as: UTF8.self))}"
        return try #require(try ChatWorkoutReply.parseIfPresent(json))
    }
    @Test func copiedContextIsExplicitAndRespectsSharingPreferences() throws {
        var state = PhoneState(); state.plan = try PlanImport.parse(PlanImport.example)
        state.profile = "PRIVATE-PROFILE"; state.contextProfileApproved = false
        state.contextHistoryApproved = false
        let before = state.plan
        let packet = try state.prepareChatHandoff(request: "Today is legs")
        #expect(state.plan == before && state.sessions.isEmpty)
        #expect(packet.prompt.contains(packet.id.uuidString))
        #expect(packet.prompt.contains("Today is legs") && packet.prompt.contains("loadIsUnspecified"))
        #expect(!packet.prompt.contains("PRIVATE-PROFILE"))
        #expect(packet.context.contains("CURRENT SAVED PLAN"))
        #expect(!state.chatHasNewContext)
        #expect(try state.prepareChatHandoff(request: "Today is legs").id == packet.id)
        state.contextProfileApproved = true
        #expect(state.chatHasNewContext)
        #expect(try state.prepareChatHandoff(request: "Today is legs").prompt.contains("PRIVATE-PROFILE"))
    }
    @Test func correlatedReplyRequiresAcceptanceAndSurvivesRelaunch() throws {
        var state = PhoneState(); let old = try PlanImport.parse(PlanImport.example); state.plan = old
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let packet = try state.prepareChatHandoff(request: "Legs", now: now)
        var proposed = old; proposed.id = UUID(); proposed.title = "Pierna"
        let response = try reply(packet, plan: proposed)
        try state.validateChatReply(response.handoffID)
        #expect(state.plan == old) // preview is read-only
        var edited = proposed; edited.exercises[0].restSeconds = 120
        try state.acceptChatReply(response, editedPlan: edited, useToday: true, now: now)
        #expect(state.plan == edited && state.sessions.isEmpty && !state.chatHasNewContext)
        #expect(state.routineLibrary.contains { $0.plan == old })
        #expect(state.unlinkedCoachReviews?.last?.response.plan == proposed)
        let loaded = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(state))
        #expect(loaded == state && loaded.chatHandoff?.acceptedAt != nil)
        let accepted = state
        #expect(throws: WorkoutError.self) { try state.acceptChatReply(response, editedPlan: edited, useToday: true) }
        #expect(state == accepted)
    }
    @Test func freshRecordsMakeAnOpenReplyStaleAndRemainInHistory() throws {
        var state = PhoneState(); let plan = try PlanImport.parse(PlanImport.example); state.plan = plan
        let packet = try state.prepareChatHandoff(request: "Next workout")
        let response = try reply(packet, plan: plan)
        var session = try WorkoutSession(plan: plan, now: Date(timeIntervalSince1970: 1_700_000_000))
        try session.logSet(weight: 22, reps: 9, now: session.startedAt.addingTimeInterval(10), uptime: 100)
        session.finish(now: session.startedAt.addingTimeInterval(11))
        try state.receive(session)
        #expect(state.chatHasNewContext)
        let before = state
        #expect(throws: WorkoutError.self) { try state.acceptChatReply(response, editedPlan: plan, useToday: true) }
        #expect(state == before && state.sessions.count == 1)
        let next = try state.prepareChatHandoff(request: "Next workout")
        #expect(next.id != packet.id && next.context.contains(session.id.uuidString))
        #expect(throws: WorkoutError.self) { try state.validateChatReply(packet.id) }
    }
    @Test func replyCannotBypassCorrelationViaLegacyOrShortcutImport() throws {
        var state = PhoneState(); let plan = try PlanImport.parse(PlanImport.example)
        let packet = try state.prepareChatHandoff(request: "")
        let planText = String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
        let json = "{\"handoffID\":\"\(packet.id)\",\"analysis\":\"OK\",\"plan\":\(planText)}"
        #expect(try ChatWorkoutReply.parseIfPresent("```json\n" + json + "\n```") != nil)
        #expect(throws: WorkoutError.self) { try PlanImport.parse(json) }
        #expect(throws: WorkoutError.self) { try PlanImport.parseReview(json) }
        #expect(throws: WorkoutError.self) { try SmartWorkoutImport.extract(json) }
        #expect(throws: WorkoutError.self) { try state.receiveReview(json) }
        #expect(try ChatWorkoutReply.parseIfPresent(PlanImport.example) == nil)
        #expect(try ChatWorkoutReply.parseIfPresent("Prensa 3 x 10") == nil)
        #expect(throws: WorkoutError.self) { try ChatWorkoutReply.parseIfPresent(json.replacingOccurrences(of: "\"analysis\"", with: "\"reviewAttemptID\":\"forged\",\"analysis\"")) }
        #expect(throws: WorkoutError.self) { try ChatWorkoutReply.parseIfPresent(json.replacingOccurrences(of: "\"analysis\"", with: "\"handoffID\":\"duplicate\",\"analysis\"")) }
    }
    @Test func libraryAcceptanceDoesNotReplaceTodayAndFailureIsAtomic() throws {
        var state = PhoneState(); let old = try PlanImport.parse(PlanImport.example); state.plan = old
        let packet = try state.prepareChatHandoff(request: "Another routine")
        var plan = old; plan.id = UUID(); plan.title = "For later"
        let response = try reply(packet, plan: plan)
        var invalid = plan; invalid.exercises[0].sets = 0
        let before = state
        #expect(throws: WorkoutError.self) { try state.acceptChatReply(response, editedPlan: invalid, useToday: false) }
        #expect(state == before)
        try state.acceptChatReply(response, editedPlan: plan, useToday: false)
        #expect(state.plan == old && state.routineLibrary.contains { $0.plan == plan })
        #expect(throws: WorkoutError.self) { try state.prepareChatHandoff(request: String(repeating: "x", count: 1001)) }
    }
    @Test func fractionalFinishTimeDoesNotInvalidateContextOnRelaunch() throws {
        var state = PhoneState(); var plan = try PlanImport.parse(PlanImport.example)
        plan.timeBudget = TimeBudget(durationMinutes: nil, finishAt: Date(timeIntervalSince1970: 1_800_000_000.1234567))
        state.plan = plan
        let packet = try state.prepareChatHandoff(request: "Same workout")
        let loaded = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(state))
        #expect(!loaded.chatHasNewContext)
        try loaded.validateChatReply(packet.id)
    }
}
