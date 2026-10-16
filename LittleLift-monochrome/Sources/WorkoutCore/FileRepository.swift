import Foundation

/// One instance per process, owned by its main-actor store. Writes replace the file atomically.
public struct FileRepository<State: Codable> {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> State? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Self.decoder().decode(State.self, from: Data(contentsOf: url))
    }

    /// One-time, protected migration checkpoint. Never overwrites a prior backup.
    public func checkpointBeforeUpgrade() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let backup = url.deletingPathExtension().appendingPathExtension("pre-build11.json")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        let original = try Data(contentsOf: url)
        _ = try Self.decoder().decode(State.self, from: original)
        #if os(iOS) || os(watchOS)
        try original.write(to: backup, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try original.write(to: backup, options: [.atomic])
        #endif
    }

    public func save(_ state: State) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder().encode(state)
        #if os(iOS) || os(watchOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]; return encoder
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970; return decoder
    }
}

public enum SyncCodec {
    public static func encode(_ message: SyncMessage) throws -> Data {
        let data = try FileRepository<PhoneState>.encoder().encode(message)
        guard data.count < 60_000 else { throw WorkoutError.invalidInput(L10n.s("This workout is too large to send to the watch.")) }
        return data
    }
    public static func decode(_ data: Data) throws -> SyncMessage {
        guard data.count < 60_000 else { throw WorkoutError.invalidInput(L10n.s("The received workout is too large.")) }
        let message = try FileRepository<PhoneState>.decoder().decode(SyncMessage.self, from: data)
        switch message {
        case .snapshot(let snapshot): try SyncLogic.validate(snapshot)
        case .completed(let workout): try workout.validateCompleted()
        case .requestSnapshot, .planReceived: break
        }
        return message
    }
}

/// Refuse a future schema instead of silently writing it back as an older version.
public enum StorageSchema {
    public static func validate(_ version: Int?) throws {
        guard version == nil || (1...2).contains(version!) else {
            throw WorkoutError.invalidInput(L10n.s("This data was saved by a newer app version. Update Little Lift; the original file is preserved."))
        }
    }
}
