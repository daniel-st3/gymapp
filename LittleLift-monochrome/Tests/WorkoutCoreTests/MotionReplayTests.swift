import Foundation
import Testing
@testable import WorkoutCore

struct MotionReplayTests {
    // Synthetic signals test code invariants only. They are not personal training
    // data, a trained model, or evidence of physical rep-count accuracy.
    func fixture() -> MotionRecording {
        var r = MotionRecording(exercise: "Dumbbell curl")
        r.samples = (0..<500).map { i in let t = Double(i)/25; return MotionSample(t:t,x:sin(t * .pi),y:0,z:0) }
        r.status = "stopped"; return r
    }
    @Test func movementSelectionSyncsAndOlderSettingsRemainCompatible() throws {
        var phone = PhoneState(); phone.motionOptIn = true; phone.motionExercise = .lateralRaise
        let snapshot = SyncLogic.snapshot(from: phone)
        var watch = WatchState(); _ = try SyncLogic.watchReply(to: snapshot, state: &watch)
        #expect(watch.motionExercise == .lateralRaise && watch.motionOptIn == true)
        let old = try FileRepository<PhoneSnapshot>.decoder().decode(PhoneSnapshot.self, from: Data(#"{"acknowledged":[]}"#.utf8))
        #expect(old.motionExercise == nil && old.motionOptIn == nil)
        let invalid = Data(#"{"acknowledged":[],"motionExercise":"run arbitrary code"}"#.utf8)
        #expect(throws: (any Error).self) { try FileRepository<PhoneSnapshot>.decoder().decode(PhoneSnapshot.self, from: invalid) }
    }
    @Test func syntheticTimingMarkersRemainUnconfirmedAndEditable() throws {
        var r = fixture(); try r.validate()
        #expect((9...11).contains(r.suggestedMarkers.count))
        #expect(r.confirmedReps == nil)
        let original = r.samples; try r.confirm(reps: 7)
        #expect(r.confirmedReps == 7 && r.samples == original)
    }
    @Test func gapsAndInvalidTimestampsAreNotInventedAway() throws {
        var r = fixture(); r.samples.removeSubrange(100..<150)
        #expect(r.gaps.count == 1)
        r.samples.append(r.samples[0])
        #expect(throws: (any Error).self) { try r.validate() }
    }
    @Test func duplicateTransferPreservesConfirmationAndRejectsChangedOriginal() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = MotionRepository(folder: dir)
        let original = fixture(); let bytes = try FileRepository<MotionRecording>.encoder().encode(original)
        try repository.receive(bytes)
        var confirmed = original; try confirmed.confirm(reps: 6); try repository.save(confirmed)
        try repository.receive(bytes)
        #expect(try repository.recordings().first?.confirmedReps == 6)
        var changed = original; changed.samples.removeLast()
        #expect(throws: (any Error).self) { try repository.receive(FileRepository<MotionRecording>.encoder().encode(changed)) }
    }
    @Test func emptyAndStationaryCaptureDoNotProduceFabricatedRepetitions() throws {
        var r = MotionRecording(exercise: "Lateral raise")
        #expect(r.suggestedMarkers.isEmpty)
        r.samples = (0..<100).map { MotionSample(t: Double($0)/25,x:0,y:0,z:0) }
        #expect(r.suggestedMarkers.isEmpty)
        #expect(throws: (any Error).self) { try r.confirm(reps: 5) }
    }
}
