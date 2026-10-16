import Foundation
import Testing
@testable import WorkoutCore

struct ObservationTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func plan() throws -> WorkoutPlan { try PlanImport.parse(PlanImport.observationExample) }
    private func logged() throws -> WorkoutSession {
        var session = try WorkoutSession(plan: plan(), now: start)
        try session.logSet(weight: 4.5, reps: 6, now: start.addingTimeInterval(10), uptime: 1000)
        session.skipRest()
        try session.logSet(weight: 5, reps: 8, now: start.addingTimeInterval(80), uptime: 1070)
        return session
    }
    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try FileRepository<T>.decoder().decode(T.self, from: FileRepository<T>.encoder().encode(value))
    }

    @Test func legacyImportAndSavedSessionRetainTheirValuesWithoutMeasurements() throws {
        let old = try PlanImport.parse(PlanImport.example)
        #expect(old.observations == nil)
        var session = try WorkoutSession(plan: old, now: start)
        try session.logSet(weight: 42.5, reps: 8, now: start)
        session.finish(now: start)
        var object = try #require(JSONSerialization.jsonObject(with: FileRepository<WorkoutSession>.encoder().encode(session)) as? [String: Any])
        object.removeValue(forKey: "effortResponse")
        var legacyEntries = object["entries"] as! [[String: Any]]
        for i in legacyEntries.indices { legacyEntries[i].removeValue(forKey: "loggedUptime") }
        object["entries"] = legacyEntries
        let restored = try FileRepository<WorkoutSession>.decoder().decode(WorkoutSession.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.entries[0].weight == session.entries[0].weight && restored.entries[0].reps == session.entries[0].reps)
        #expect(restored.observationEvidence.isEmpty)
        #expect(restored.entries[0].loggedUptime == nil)
        try restored.validateCompleted()
    }

    @Test func importsStableIDsAndReviewUsesTheSameSchema() throws {
        let first = try plan(), second = try plan()
        #expect(first.exercises == second.exercises)
        #expect(first.observations == second.observations)
        #expect(first.id != second.id) // each accepted workout gets its own plan identity
        #expect(try PlanImport.parseReview("{\"analysis\":\"Generic feedback\",\"plan\":\(PlanImport.observationExample)}").plan.observations == first.observations)
        #expect(first.observationRequests.allSatisfy { !$0.collectionDescription(in: first).isEmpty })
    }

    @Test func unsupportedRequestsExplainWhatIsSupported() throws {
        let text = PlanImport.observationExample.replacingOccurrences(of: "loggingInterval", with: "actualRest")
        do { _ = try PlanImport.parse(text); Issue.record("Unsupported request accepted") }
        catch { #expect(error.localizedDescription.contains("Unsupported observation")) }
        do { _ = try PlanImport.parseReview("{\"analysis\":\"x\",\"plan\":\(text)}"); Issue.record("Unsupported review accepted") }
        catch { #expect(error.localizedDescription.contains("Unsupported observation")) }
    }

    @Test func rejectsUnknownOptionsAndLoadConventionsInsteadOfIgnoringThem() throws {
        for text in [PlanImport.observationExample.replacingOccurrences(of: "\"afterSet\": 2", with: "\"afterSet\": 2, \"script\": \"ignored code\""),
                     PlanImport.observationExample.replacingOccurrences(of: "perDumbbell", with: "unknownConvention")] {
            do { _ = try PlanImport.parse(text); Issue.record("Invalid option accepted") }
            catch { #expect(error.localizedDescription.contains("Unsupported")) }
        }
    }

    @Test func rejectsReferencesDuplicatesVersionAndBounds() throws {
        var p = try plan()
        p.observationSchemaVersion = 2
        #expect(throws: (any Error).self) { try p.validate() }
        p = try plan(); let duplicate = p.observationRequests[0]; p.observations?.append(duplicate)
        #expect(throws: (any Error).self) { try p.validate() }
        for request in [ObservationRequest(id: "bad", kind: .performance, exerciseID: UUID()),
                        ObservationRequest(id: String(repeating: "a", count: 65), kind: .performance, exerciseID: p.exercises[0].id),
                        ObservationRequest(id: "bad\ncode", kind: .performance, exerciseID: p.exercises[0].id),
                        ObservationRequest(id: "bad", kind: .effort, exerciseID: p.exercises[0].id, afterSet: 1),
                        ObservationRequest(id: "bad", kind: .loggingInterval, exerciseID: p.exercises[0].id, afterSet: 2)] {
            p = try plan(); p.observations = [request]
            #expect(throws: (any Error).self) { try p.validate() }
        }
        p = try plan()
        let other = ExercisePlan(name: "Other", sets: 1, reps: 8, weight: 1)
        p.exercises.append(other)
        p.observations?.append(ObservationRequest(id: "second-effort", kind: .effort, exerciseID: other.id, afterSet: 1))
        #expect(throws: (any Error).self) { try p.validate() }
    }

    @Test func pendingEffortSurvivesRelaunchAndCannotBeDeliveredPrematurely() throws {
        var watch = WatchState(); watch.session = try logged()
        watch.enqueueCompleted()
        #expect(watch.outbox.isEmpty)
        watch = try roundTrip(watch)
        #expect(watch.session?.pendingEffort?.id == "press-effort")
        var phone = PhoneState()
        #expect(throws: (any Error).self) { try phone.receive(#require(watch.session)) }
        try watch.session?.answerEffort(7, now: start.addingTimeInterval(85))
        watch.enqueueCompleted()
        #expect(watch.outbox.count == 1)
        #expect(watch.outbox[0].effortResponse?.rating == 7)
    }

    @Test func skippedEffortIsNotAZeroOrDefaultRating() throws {
        var session = try logged()
        try session.answerEffort(nil, now: start.addingTimeInterval(85))
        #expect(session.pendingEffort == nil)
        #expect(session.effortResponse?.rating == nil)
        #expect(session.report().contains("Skipped: no effort rating supplied"))
        try session.validateCompleted()
    }

    @Test func invalidEffortDoesNotMutateAndCannotOverwriteAnswer() throws {
        var session = try logged()
        for rating in [-1, 0, 11] { #expect(throws: (any Error).self) { try session.answerEffort(rating, now: start.addingTimeInterval(85)) } }
        #expect(session.effortResponse == nil)
        try session.answerEffort(7, now: start.addingTimeInterval(85))
        #expect(throws: (any Error).self) { try session.answerEffort(8, now: start.addingTimeInterval(86)) }
        #expect(session.effortResponse?.rating == 7)
    }

    @Test func undoRemovesRatingAndTimingOfRemovedSet() throws {
        var p = try plan()
        p.exercises.append(ExercisePlan(name: "Next", sets: 1, reps: 8, weight: 5))
        var session = try WorkoutSession(plan: p, now: start)
        try session.logSet(weight: 4, reps: 6, now: start.addingTimeInterval(10), uptime: 1000)
        session.skipRest()
        try session.logSet(weight: 4, reps: 7, now: start.addingTimeInterval(60), uptime: 1050)
        try session.answerEffort(9, now: start.addingTimeInterval(65))
        try session.undoLastSet()
        #expect(session.effortResponse == nil)
        #expect(session.pendingEffort == nil)
        #expect(session.entries.count == 1)
        try session.logSet(weight: 4.5, reps: 8, now: start.addingTimeInterval(80), uptime: 1070)
        #expect(session.pendingEffort != nil)
        #expect(session.loggingInterval(before: session.entries[1]) == 70)
        #expect(!session.report().contains("9/10"))
    }

    @Test func continuingWithoutAnswerSkipsItAndUndoOfNextSetKeepsThatSkip() throws {
        var p = try plan(); p.exercises[0].sets = 1; p.exercises[0].restSeconds = 0
        p.observations = [ObservationRequest(id: "effort", kind: .effort, exerciseID: p.exercises[0].id, afterSet: 1)]
        p.exercises.append(ExercisePlan(name: "Next", sets: 2, reps: 8, weight: 1))
        var session = try WorkoutSession(plan: p, now: start)
        try session.logSet(weight: 5, reps: 8, now: start)
        try session.logSet(weight: 1, reps: 8, now: start.addingTimeInterval(10))
        #expect(session.pendingEffort == nil)
        #expect(session.effortResponse?.setID == session.entries[0].id)
        try session.undoLastSet()
        #expect(session.effortResponse?.setID == session.entries[0].id)
    }

    @Test func earlyFinishReportsUnreachedFinalSetAndMissingActuals() throws {
        var session = try WorkoutSession(plan: plan(), now: start)
        try session.logSet(weight: 4.5, reps: 6, now: start.addingTimeInterval(10))
        session.finish(now: start.addingTimeInterval(20))
        let report = session.report()
        #expect(report.contains("requested final set was not logged"))
        #expect(report.contains("Unavailable: set not logged; no actual values inferred"))
        #expect(report.contains("Completed: 1 / 2"))
        #expect(session.effortResponse == nil)
        try session.validateCompleted()
    }

    @Test func reportAndShortcutContextSeparateTargetsActualsAndTiming() throws {
        var session = try logged()
        try session.answerEffort(7, now: start.addingTimeInterval(90))
        let report = session.report()
        #expect(report.contains("Prescribed: 5 kg × 8 reps"))
        #expect(report.contains("User-confirmed: \(WorkoutSession.number(4.5)) kg × 6 reps"))
        #expect(report.contains("Log-tap interval: 70 s"))
        #expect(report.contains("Prescribed rest: 30 s"))
        #expect(report.contains("Includes exercise time; not actual rest"))
        #expect(report.contains("7/10"))
        #expect(report.contains(session.entries[0].id.uuidString))
        #expect(PlanImport.reviewPrompt(profile: "Generic", sessions: [session]).contains(report))
    }

    @Test func clockChangesRebootsAndHistoricalDatesCannotInventIntervals() throws {
        for uptime in [5.0, 1020, 50_000] {
            var session = try WorkoutSession(plan: plan(), now: start)
            try session.logSet(weight: 5, reps: 8, now: start.addingTimeInterval(10), uptime: 1000)
            session.skipRest()
            try session.logSet(weight: 5, reps: 8, now: start.addingTimeInterval(80), uptime: uptime)
            #expect(session.loggingInterval(before: session.entries[1]) == nil)
        }
        var session = try logged()
        var object = try #require(JSONSerialization.jsonObject(with: FileRepository<WorkoutSession>.encoder().encode(session)) as? [String: Any])
        var entries = try #require(object["entries"] as? [[String: Any]])
        for i in entries.indices { entries[i].removeValue(forKey: "loggedUptime") }
        object["entries"] = entries
        session = try FileRepository<WorkoutSession>.decoder().decode(WorkoutSession.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(session.loggingInterval(before: session.entries[1]) == nil)
    }

    @Test func comparisonRequiresExactVariationUnitsAndLoadConvention() throws {
        let a = try plan().exercises[0]
        var b = a
        #expect(a.matches(b, unit: .kg, otherUnit: .kg))
        b.comparisonID = "standing-db-press"
        #expect(!a.matches(b, unit: .kg, otherUnit: .kg))
        b = a; b.loadConvention = .total
        #expect(!a.matches(b, unit: .kg, otherUnit: .kg))
        b = a
        #expect(!a.matches(b, unit: .kg, otherUnit: .lb))
        b.comparisonID = nil; b.loadConvention = nil
        #expect(!b.matches(b, unit: .kg, otherUnit: .kg))
    }

    @Test func proposalsCannotReplacePlanUntilAcceptedAndPersistAcrossRelaunch() throws {
        var phone = PhoneState(); phone.plan = try PlanImport.parse(PlanImport.example)
        let oldID = phone.plan?.id
        try phone.propose(TrainingReview(analysis: "Generic descriptive feedback", plan: plan()))
        phone = try roundTrip(phone)
        #expect(phone.plan?.id == oldID)
        #expect(phone.review?.plan.observationRequests.count == 3)
        try phone.acceptReview()
        #expect(phone.plan?.id != oldID)
        #expect(phone.review == nil)
    }

    @Test func evidenceSurvivesDuplicateSyncAndDurableAcknowledgement() throws {
        var session = try logged(); try session.answerEffort(6, now: start.addingTimeInterval(90))
        var watch = WatchState(); watch.session = session; watch.enqueueCompleted()
        var phone = PhoneState()
        for _ in 0..<2 {
            let message = try SyncCodec.decode(SyncCodec.encode(.completed(session)))
            let reply = try #require(try SyncLogic.phoneReply(to: message, state: &phone, now: start.addingTimeInterval(100)))
            phone = try roundTrip(phone) // durable storage before receipt
            guard case .snapshot(let snapshot) = reply else { Issue.record("Wrong reply"); return }
            _ = try SyncLogic.watchReply(to: snapshot, state: &watch)
        }
        #expect(phone.sessions == [session])
        #expect(watch.outbox.isEmpty)
        #expect(try roundTrip(watch).recent[0].effortResponse?.rating == 6)
    }

    @Test func malformedReceivedEvidenceCannotBeAcknowledged() throws {
        var session = try logged(); try session.answerEffort(6, now: start.addingTimeInterval(90))
        var object = try #require(JSONSerialization.jsonObject(with: FileRepository<WorkoutSession>.encoder().encode(session)) as? [String: Any])
        var answer = try #require(object["effortResponse"] as? [String: Any]); answer["setID"] = UUID().uuidString; object["effortResponse"] = answer
        let bad = try FileRepository<WorkoutSession>.decoder().decode(WorkoutSession.self, from: JSONSerialization.data(withJSONObject: object))
        var phone = PhoneState()
        #expect(throws: (any Error).self) { try SyncLogic.phoneReply(to: .completed(bad), state: &phone) }
        #expect(phone.sessions.isEmpty)
    }

    @Test func largestObservationWorkoutFitsTransport() throws {
        var p = try plan()
        p.title = String(repeating: "x", count: 120)
        p.exercises = (0..<50).map { i in ExercisePlan(name: String(repeating: "\"", count: 120), sets: 2, reps: 200, weight: 1000, restSeconds: 0, comparisonID: String(repeating: "a", count: 62) + "\(i)", loadConvention: .total) }
        p.observations = p.exercises.prefix(6).flatMap { e in
            [ObservationRequest(id: e.id.uuidString + "-performance", kind: .performance, exerciseID: e.id), ObservationRequest(id: e.id.uuidString + "-timing", kind: .loggingInterval, exerciseID: e.id)]
        }
        var session = try WorkoutSession(plan: p, now: start)
        for i in 0..<100 { try session.logSet(weight: 1000, reps: 200, now: start.addingTimeInterval(Double(i)), uptime: 1000 + Double(i)) }
        #expect(try SyncCodec.encode(.completed(session)).count < 60_000)
    }
}
