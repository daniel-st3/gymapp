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
    public func checkpointBeforeUpgrade(suffix: String = "pre-build11") throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let backup = url.deletingPathExtension().appendingPathExtension("\(suffix).json")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        let original = try Data(contentsOf: url)
        _ = try Self.decoder().decode(State.self, from: original)
        #if os(iOS) || os(watchOS)
        try original.write(to: backup, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try original.write(to: backup, options: [.atomic])
        #endif
    }

    /// Explicit recovery only: preserve even undecodable bytes before replacing
    /// the primary file. A checkpoint or atomic-save failure leaves it intact.
    public func saveRecovery(_ state: State, checkpoint: URL) throws {
        guard !FileManager.default.fileExists(atPath: checkpoint.path), checkpoint != url else {
            throw WorkoutError.invalidState(L10n.s("The recovery checkpoint already exists. No records were changed."))
        }
        if FileManager.default.fileExists(atPath: url.path) {
            let original = try Data(contentsOf: url)
            #if os(iOS) || os(watchOS)
            try original.write(to: checkpoint, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try original.write(to: checkpoint, options: [.atomic])
            #endif
        }
        try save(state)
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
    /// Read the version independently of the payload: a future format may no
    /// longer decode as PhoneState, but must still never be replaced by recovery.
    public static func validateHeader(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["storageVersion"] != nil else { return }
        struct Header: Decodable { let storageVersion: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else {
            throw WorkoutError.invalidInput(L10n.s("This data was saved by a newer app version. Update Little Lift; the original file is preserved."))
        }
        try validate(header.storageVersion)
    }

    public static func validate(_ version: Int?) throws {
        guard version == nil || (1...3).contains(version!) else {
            throw WorkoutError.invalidInput(L10n.s("This data was saved by a newer app version. Update Little Lift; the original file is preserved."))
        }
    }
}
