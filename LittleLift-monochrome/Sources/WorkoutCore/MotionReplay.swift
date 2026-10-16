import Foundation

public enum MotionExercise: String, Codable, CaseIterable, Sendable {
    case dumbbellCurl = "Dumbbell curl"
    case lateralRaise = "Lateral raise"
}

public struct MotionSample: Codable, Equatable, Sendable {
    public let t: Double
    public let x: Double
    public let y: Double
    public let z: Double
    public init(t: Double, x: Double, y: Double, z: Double) { self.t = t; self.x = x; self.y = y; self.z = z }
}
public struct MotionRecording: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let exercise: String
    public let startedAt: Date
    public var samples: [MotionSample]
    public var status: String
    public var confirmedReps: Int?
    public var confirmedAt: Date?
    public var batteryStart: Double?
    public var batteryEnd: Double?
    public init(id: UUID = UUID(), exercise: String, now: Date = Date()) {
        self.id = id; self.exercise = exercise; self.startedAt = now; samples = []; status = "recording"
    }
    public func validate() throws {
        guard ["Dumbbell curl", "Lateral raise"].contains(exercise), ["recording", "stopped", "interrupted", "time limit"].contains(status),
              samples.count <= 4500, InputBoundary.validDate(startedAt), confirmedAt.map({ InputBoundary.validDate($0) && $0 >= startedAt && status != "recording" }) ?? true, confirmedReps.map({ (0...200).contains($0) }) ?? true, (confirmedReps == nil) == (confirmedAt == nil), [batteryStart, batteryEnd].compactMap({ $0 }).allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw WorkoutError.invalidInput("Invalid experimental motion recording.") }
        var previous = -1.0
        for s in samples {
            guard [s.t,s.x,s.y,s.z].allSatisfy(\.isFinite), s.t > previous, (0...185).contains(s.t), [s.x,s.y,s.z].allSatisfy({ abs($0) <= 100 }) else { throw WorkoutError.invalidInput("Motion timestamps or sample values are invalid.") }
            previous = s.t
        }
    }
    public var duration: Double { samples.last?.t ?? 0 }
    public var gaps: [Double] { zip(samples, samples.dropFirst()).filter { $1.t - $0.t > 0.16 }.map { $0.1.t } }
    /// Local signal-processing hypothesis, not a trained model or validated rep counter.
    /// Positive peaks of the dominant rotation axis avoid counting both directions
    /// as separate repetitions, but wrist orientation and unrelated movement can fail.
    public var suggestedMarkers: [Double] {
        guard samples.count >= 25 else { return [] }
        let energies = [samples.map(\.x), samples.map(\.y), samples.map(\.z)].map { $0.reduce(0) { $0 + $1 * $1 } }
        let axis = energies.enumerated().max { $0.element < $1.element }?.offset ?? 0
        let values = samples.map { [ $0.x, $0.y, $0.z ][axis] }
        let peak = values.max() ?? 0
        guard peak >= 0.6 else { return [] }
        let threshold = max(0.6, peak * 0.4)
        var result: [Double] = []
        for i in 2..<(samples.count - 2) {
            let local = (values[i-1] + values[i] + values[i+1]) / 3
            if local > threshold, values[i] > values[i-1], values[i] >= values[i+1],
               samples[i].t - (result.last ?? -10) >= 0.8,
               samples[i].t - samples[i-1].t <= 0.16 {
                result.append(samples[i].t)
            }
        }
        return Array(result.prefix(200))
    }
    public var suggestedSets: [[Double]] {
        var sets: [[Double]] = []
        for marker in suggestedMarkers {
            if let last = sets.last?.last, marker - last <= 8 { sets[sets.count - 1].append(marker) }
            else { sets.append([marker]) }
        }
        return sets
    }
    public mutating func confirm(reps: Int, now: Date = Date()) throws {
        guard status != "recording", (0...200).contains(reps) else { throw WorkoutError.invalidInput("Confirm a count from 0–200 after capture stops.") }
        confirmedReps = reps; confirmedAt = now
    }
}

public struct MotionRepository {
    public let folder: URL
    public init(folder: URL) { self.folder = folder }
    public func save(_ recording: MotionRecording) throws {
        try recording.validate()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        var localFolder = folder; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try localFolder.setResourceValues(values)
        #endif
        try FileRepository<MotionRecording>(url: url(recording.id)).save(recording)
    }
    public func url(_ id: UUID) -> URL { folder.appendingPathComponent(id.uuidString + ".json") }
    public func recordings() throws -> [MotionRecording] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        let records = try files.compactMap { try FileRepository<MotionRecording>(url: $0).load() }
        try records.forEach { try $0.validate() }; return records.sorted { $0.startedAt > $1.startedAt }
    }
    public func receive(_ data: Data) throws {
        guard data.count <= 2_000_000 else { throw WorkoutError.invalidInput("Motion recording exceeds the local transfer limit.") }
        let received = try FileRepository<MotionRecording>.decoder().decode(MotionRecording.self, from: data)
        try received.validate()
        guard received.status != "recording" else { throw WorkoutError.invalidInput("Only stopped motion recordings can be imported.") }
        if let existing = try FileRepository<MotionRecording>(url: url(received.id)).load() {
            guard existing.samples == received.samples, existing.exercise == received.exercise, existing.startedAt == received.startedAt else { throw WorkoutError.invalidInput("A different original motion record already has this ID.") }
            return // preserve user confirmation when an original is delivered twice
        }
        guard try recordings().count < 20 else { throw WorkoutError.invalidInput("The experimental library is limited to 20 recordings. Export/delete a recording before adding more.") }
        try save(received)
    }
    public func delete(_ id: UUID) throws { try FileManager.default.removeItem(at: url(id)) }
}
