import Foundation
import Testing
@testable import WorkoutCore

struct SecurityTests {
    private func completed(id: UUID = UUID(), weight: Double = 10) throws -> WorkoutSession {
        let plan = WorkoutPlan(title: "Fixture", exercises: [ExercisePlan(name: "Press", sets: 2, reps: 8, weight: 10, restSeconds: 0)])
        var session = try WorkoutSession(id: id, plan: plan, now: Date(timeIntervalSince1970: 1000))
        try session.logSet(weight: weight, reps: 8, now: Date(timeIntervalSince1970: 1010))
        try session.logSet(weight: weight, reps: 8, now: Date(timeIntervalSince1970: 1020))
        return session
    }
    @Test func conflictingDeliveryDoesNotAcknowledgeOrReplaceOriginal() throws {
        let original = try completed(); var phone = PhoneState()
        _ = try SyncLogic.phoneReply(to: .completed(original), state: &phone)
        let before = phone
        let conflict = try completed(id: original.id, weight: 25)
        #expect(throws: (any Error).self) { try SyncLogic.phoneReply(to: .completed(conflict), state: &phone) }
        #expect(phone == before)
        _ = try SyncLogic.phoneReply(to: .completed(original), state: &phone)
        #expect(phone == before)
        let restored = try FileRepository<PhoneState>.decoder().decode(PhoneState.self, from: FileRepository<PhoneState>.encoder().encode(phone))
        #expect(restored == before)
    }
    @Test func malformedReceiptsCannotClearOutbox() throws {
        var watch = WatchState(); watch.session = try completed(); watch.enqueueCompleted(); let before = watch
        let id = try #require(watch.session?.id)
        for snapshot in [PhoneSnapshot(plan: nil, acknowledged: [id,id]), PhoneSnapshot(plan: nil, acknowledged: [id], issuedAt: Date(timeIntervalSince1970: 1e100)), PhoneSnapshot(plan: nil, acknowledged: (0..<202).map { _ in UUID() })] {
            #expect(throws: (any Error).self) { try SyncLogic.watchReply(to: snapshot, state: &watch) }
            #expect(watch == before)
        }
    }
    @Test func decoderRejectsInvalidCompletedPayloadBeforeStore() throws {
        let session = try completed()
        let data = try FileRepository<WorkoutSession>.encoder().encode(session)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for field in ["timestamp", "sequence", "date"] {
            var changed = object
            var entries = try #require(changed["entries"] as? [[String: Any]])
            if field == "timestamp" { entries[1]["completedAt"] = 1005000 }
            if field == "sequence" { entries[0]["setNumber"] = 2; entries[1]["setNumber"] = 1 }
            if field == "date" { changed["endedAt"] = 1e100 }
            changed["entries"] = entries
            let invalid = try FileRepository<WorkoutSession>.decoder().decode(WorkoutSession.self, from: JSONSerialization.data(withJSONObject: changed))
            let packet = try SyncCodec.encode(.completed(invalid))
            #expect(throws: (any Error).self) { try SyncCodec.decode(packet) }
        }
        #expect(throws: (any Error).self) { try SyncCodec.decode(Data(repeating: 32, count: 60_000)) }
    }
    @Test func boundedFileReaderRejectsOversizeDirectoriesAndRemoteURLs() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("fixture.json")
        try Data(repeating: 65, count: 65_537).write(to: file)
        #expect(throws: (any Error).self) { try InputBoundary.read(file, maximumBytes: 64_000) }
        #expect(try InputBoundary.read(file, maximumBytes: 65_537).count == 65_537)
        #expect(throws: (any Error).self) { try InputBoundary.read(folder, maximumBytes: 64_000) }
        #expect(throws: (any Error).self) { try InputBoundary.read(URL(string: "https://example.invalid/workout")!, maximumBytes: 64_000) }
        #expect(throws: (any Error).self) { try InputBoundary.read(file, maximumBytes: Int.max) }
    }
    @Test func failedSaveCannotDamagePreviousDurableHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileRepository<PhoneState>(url: folder.appendingPathComponent("phone.json"))
        var state = PhoneState(); try state.receive(completed()); try repository.save(state)
        let invalidDestination = FileRepository<PhoneState>(url: repository.url.appendingPathComponent("blocked.json"))
        #expect(throws: (any Error).self) { try invalidDestination.save(PhoneState()) }
        #expect(try repository.load() == state)
    }
    @Test func invalidMotionConfirmationIsRejected() throws {
        var recording = MotionRecording(exercise: "Dumbbell curl", now: Date(timeIntervalSince1970: 1000)); recording.status = "stopped"
        recording.confirmedReps = 5; recording.confirmedAt = Date(timeIntervalSince1970: 999)
        #expect(throws: (any Error).self) { try recording.validate() }
    }
}
