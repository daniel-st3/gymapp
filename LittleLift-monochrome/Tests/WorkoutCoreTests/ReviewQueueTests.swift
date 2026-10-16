import Foundation
import Testing
@testable import WorkoutCore

struct ReviewQueueTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func completed() throws -> WorkoutSession {
        var s = try WorkoutSession(plan: PlanImport.parse(PlanImport.example), now: now)
        try s.logSet(weight: 40, reps: 8, now: now, uptime: 100); s.finish(now: now); return s
    }
    func response(_ ticket: ReviewTicket) -> String {
        "{\"reviewSessionID\":\"\(ticket.sessionID)\",\"reviewAttemptID\":\"\(ticket.attemptID)\",\"analysis\":\"Generic descriptive feedback\",\"plan\":\(PlanImport.example)}"
    }
    @Test func receiptQueueDeduplicatesDeliveryAndConcurrentPreparation() throws {
        var state = PhoneState(); let s = try completed()
        try state.receive(s); try state.receive(s)
        #expect(state.reviewQueue.count == 1)
        let ticket = try state.beginReview(now: now)
        #expect(throws: (any Error).self) { try state.beginReview(now: now.addingTimeInterval(1)) }
        #expect(try state.prompt(for: ticket).contains(ticket.attemptID.uuidString))
        let restored = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(state))
        #expect(restored.reviewQueue == state.reviewQueue)
    }
    @Test func successfulReviewIsIdempotentAndPlanRequiresAcceptance() throws {
        var state = PhoneState(); let s = try completed(); try state.receive(s); state.plan = s.plan
        let original = state.plan; let ticket = try state.beginReview(now: now)
        try state.receiveReview(response(ticket)); let proposal = state.review
        try state.receiveReview(response(ticket))
        #expect(state.review == proposal && state.plan == original)
        #expect(state.reviewQueue.first?.status == .received)
        try state.acceptReview(); #expect(state.plan == proposal?.plan)
    }
    @Test func cancelledAndStaleResponsesCannotReplaceNewAttempt() throws {
        var state = PhoneState(); let s = try completed(); try state.receive(s)
        let first = try state.beginReview(now: now)
        try state.endReview(s.id, cancelled: true, detail: "Cancelled")
        #expect(throws: (any Error).self) { try state.receiveReview(response(first)) }
        let second = try state.beginReview(sessionID: s.id, now: now.addingTimeInterval(2))
        #expect(throws: (any Error).self) { try state.receiveReview(response(first)) }
        try state.receiveReview(response(second)); #expect(state.review != nil)
    }
    @Test func invalidModelResultDoesNotLoseRunningReceiptOrOverwritePlan() throws {
        var state = PhoneState(); let s = try completed(); try state.receive(s)
        _ = try state.beginReview(now: now)
        #expect(throws: (any Error).self) { try state.receiveReview("not JSON") }
        #expect(state.reviewQueue.first?.status == .running && state.review == nil)
        try state.endReview(s.id, cancelled: false, detail: "Model error")
        #expect(state.reviewQueue.first?.status == .failed)
    }
    @Test func timeoutPermitsExplicitRetryAndRejectsOldResult() throws {
        var state = PhoneState(); let s = try completed(); try state.receive(s)
        let old = try state.beginReview(now: now)
        let fresh = try state.beginReview(sessionID: s.id, now: now.addingTimeInterval(601))
        #expect(old != fresh)
        #expect(throws: (any Error).self) { try state.receiveReview(response(old)) }
    }
    @Test func visibleLogActionRejectsDuplicateAndModalActions() throws {
        var p = try PlanImport.parse(PlanImport.example); p.exercises[0].restSeconds = 0
        var session = try WorkoutSession(plan: p, now: now)
        #expect(LogActionGuard.allows(session: session, presentedSheet: false, now: now))
        try session.logSet(weight: 40, reps: 8, now: now, uptime: 100)
        #expect(!LogActionGuard.allows(session: session, presentedSheet: false, now: now.addingTimeInterval(1)))
        #expect(LogActionGuard.allows(session: session, presentedSheet: false, now: now.addingTimeInterval(2)))
        #expect(!LogActionGuard.allows(session: session, presentedSheet: true, now: now.addingTimeInterval(3)))
    }
    @Test func malformedReceiptCannotFallBackToUnboundManualProposal() throws {
        var state = PhoneState()
        let text = "{\"reviewSessionID\":\"bad\",\"reviewAttemptID\":\"bad\",\"analysis\":\"generic\",\"plan\":" + PlanImport.example + "}"
        #expect(throws: (any Error).self) { try state.receiveReview(text) }
        #expect(state.review == nil)
    }

}
