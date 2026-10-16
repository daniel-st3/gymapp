import Foundation
import Testing
@testable import WorkoutCore

struct SyncTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func watchRequestsTheActualSavedPlanAndPhoneReceivesAPlanReceipt() throws {
        var phone = PhoneState()
        phone.plan = try PlanImport.parse(PlanImport.example)
        var watch = WatchState()
        let request = try SyncCodec.decode(SyncCodec.encode(.requestSnapshot))
        let reply = try #require(try SyncLogic.phoneReply(to: request, state: &phone, now: now))
        guard case .snapshot(let snapshot) = try SyncCodec.decode(SyncCodec.encode(reply)) else {
            Issue.record("Request must return a snapshot directly"); return
        }
        let receipt = try #require(try SyncLogic.watchReply(to: snapshot, state: &watch))
        #expect(watch.plan?.id == phone.plan?.id)
        guard case .planReceived(let id) = try SyncCodec.decode(SyncCodec.encode(receipt)) else {
            Issue.record("A saved plan must produce a plan receipt"); return
        }
        #expect(id == phone.plan?.id)
    }

    @Test func liveWorkoutReplyAcknowledgesPersistableActualResultsAndDeduplicates() throws {
        let plan = try PlanImport.parse(PlanImport.example)
        var workout = try WorkoutSession(plan: plan, now: now)
        try workout.logSet(weight: 42.5, reps: 8, now: now)
        workout.finish(now: now.addingTimeInterval(100))
        var watch = WatchState(); watch.plan = plan; watch.session = workout; watch.enqueueCompleted()
        var phone = PhoneState(); phone.plan = plan
        for _ in 0..<2 {
            let response = try #require(try SyncLogic.phoneReply(to: .completed(workout), state: &phone, now: now))
            guard case .snapshot(let snapshot) = response else { Issue.record("Missing receipt"); return }
            _ = try SyncLogic.watchReply(to: snapshot, state: &watch)
        }
        #expect(phone.sessions.count == 1)
        #expect(watch.outbox.isEmpty)
        #expect(phone.sessions.first?.entries.first?.weight == 42.5)
    }

    @Test func delayedContextCannotReplaceANewerPlanButCanStillAcknowledgeAWorkout() throws {
        let oldPlan = try PlanImport.parse(PlanImport.example)
        let newPlan = WorkoutPlan(title: "Next workout", exercises: oldPlan.exercises)
        var workout = try WorkoutSession(plan: oldPlan, now: now)
        workout.finish(now: now)
        var watch = WatchState(); watch.session = workout; watch.enqueueCompleted()
        _ = try SyncLogic.watchReply(to: PhoneSnapshot(plan: newPlan, acknowledged: [], issuedAt: now.addingTimeInterval(10)), state: &watch)
        _ = try SyncLogic.watchReply(to: PhoneSnapshot(plan: oldPlan, acknowledged: [workout.id], issuedAt: now), state: &watch)
        #expect(watch.plan?.id == newPlan.id)
        #expect(watch.outbox.isEmpty)
    }

    @Test func previousWatchStorageAndSnapshotsStillDecode() throws {
        let oldState = Data("{\"outbox\":[],\"recent\":[],\"haptics\":true}".utf8)
        let watch = try FileRepository<WatchState>.decoder().decode(WatchState.self, from: oldState)
        #expect(watch.lastSnapshotDate == nil)
        let oldSnapshot = Data("{\"acknowledged\":[]}".utf8)
        let snapshot = try FileRepository<PhoneState>.decoder().decode(PhoneSnapshot.self, from: oldSnapshot)
        #expect(snapshot.issuedAt == .distantPast)
    }

    @Test func invalidWorkoutCannotGenerateAHistoryReceipt() throws {
        var phone = PhoneState()
        let active = try WorkoutSession(plan: PlanImport.parse(PlanImport.example), now: now)
        #expect(throws: (any Error).self) { try SyncLogic.phoneReply(to: .completed(active), state: &phone) }
        #expect(phone.sessions.isEmpty)
    }

    @Test func anEmptyPhoneReturnsAnExplicitEmptyPlanWithoutErasingAnActiveWorkout() throws {
        var phone = PhoneState()
        var watch = WatchState()
        watch.session = try WorkoutSession(plan: PlanImport.parse(PlanImport.example), now: now)
        let activeID = watch.session?.id
        let reply = try #require(try SyncLogic.phoneReply(to: .requestSnapshot, state: &phone, now: now))
        guard case .snapshot(let snapshot) = reply else { Issue.record("Missing reply"); return }
        let receipt = try SyncLogic.watchReply(to: snapshot, state: &watch)
        #expect(receipt == nil)
        #expect(watch.plan == nil)
        #expect(watch.session?.id == activeID)
    }
}
