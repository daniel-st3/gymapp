import Foundation

/// Bounds the bytes actually read, including files whose reported size changes.
/// Used only at external import boundaries; durable history has no new size cap.
public enum InputBoundary {
    public static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        guard url.isFileURL, maximumBytes > 0, maximumBytes <= 20_000_000 else {
            throw WorkoutError.invalidInput(L10n.s("Choose a local workout file."))
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw WorkoutError.invalidInput(L10n.s("Choose a regular file, not a folder.")) }
        if let size = values.fileSize, size > maximumBytes { throw tooLarge(maximumBytes) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var result = Data()
        while result.count <= maximumBytes {
            let chunk = try handle.read(upToCount: min(65_536, maximumBytes + 1 - result.count)) ?? Data()
            if chunk.isEmpty { return result }
            result.append(chunk)
        }
        throw tooLarge(maximumBytes)
    }
    private static func tooLarge(_ bytes: Int) -> WorkoutError {
        .invalidInput(L10n.s("This file is too large. Choose a file of at most \(bytes / 1000) KB."))
    }
    public static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date >= .distantPast && date <= .distantFuture
    }
}

/// Opening a shared file only supplies source text to the editable preview. It
/// never applies a plan or treats receipt-bearing coach JSON as a fresh workout.
public enum WorkoutFileImport {
    public static func readText(_ url: URL) throws -> String {
        return try text(from: InputBoundary.read(url, maximumBytes: 64_000))
    }
    public static func text(from data: Data) throws -> String {
        guard data.count <= 64_000, let text = String(data: data, encoding: .utf8) else {
            throw WorkoutError.invalidInput(L10n.s("Text imports must be UTF-8 and below 64 KB."))
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { try JSONBoundary.validate(data) }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["format"] as? String == "littlelift.workout-backup" {
            throw WorkoutError.invalidInput(L10n.s("This is a backup. Open Settings → Backups to review and restore it."))
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["reviewSessionID"] != nil || object["reviewAttemptID"] != nil || object["connectionCheckID"] != nil {
            throw WorkoutError.invalidInput(L10n.s("This is a coach response. Use Save Workout Review so its workout and attempt can be checked."))
        }
        return text
    }
}
