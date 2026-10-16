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
