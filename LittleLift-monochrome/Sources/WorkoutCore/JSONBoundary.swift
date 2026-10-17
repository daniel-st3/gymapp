import Foundation

/// Reject parser ambiguity and excessive nesting before typed decoding at an
/// external boundary. Limits apply to imports, never silently truncate history.
public enum JSONBoundary {
    public static func validate(_ data: Data) throws {
        var scanner = Scanner(bytes: Array(data))
        try scanner.value(depth: 0)
        scanner.space()
        guard scanner.index == scanner.bytes.count else { throw invalid() }
    }
    private static func invalid() -> WorkoutError {
        .invalidInput(L10n.s("JSON must have unique field names and at most 32 nested levels. No saved data was changed."))
    }
    private struct Scanner {
        let bytes: [UInt8]
        var index = 0
        var nodes = 0
        mutating func space() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        mutating func take(_ byte: UInt8) -> Bool {
            space(); guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1; return true
        }
        mutating func string(key: Bool) throws -> String {
            space(); let start = index
            guard take(34) else { throw JSONBoundary.invalid() }
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                if byte == 34 {
                    if !key { return "" }
                    guard let name = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) else { throw JSONBoundary.invalid() }
                    return name
                }
                if byte == 92 { guard index < bytes.count else { throw JSONBoundary.invalid() }; index += 1 }
                else if byte < 32 { throw JSONBoundary.invalid() }
            }
            throw JSONBoundary.invalid()
        }
        mutating func value(depth: Int) throws {
            nodes += 1
            guard depth <= 32, nodes <= 1_000_000 else { throw JSONBoundary.invalid() }
            space(); guard index < bytes.count else { throw JSONBoundary.invalid() }
            switch bytes[index] {
            case 123:
                index += 1; var keys = Set<String>()
                if take(125) { return }
                repeat {
                    let name = try string(key: true)
                    guard keys.insert(name).inserted, take(58) else { throw JSONBoundary.invalid() }
                    try value(depth: depth + 1)
                    if take(125) { return }
                    guard take(44) else { throw JSONBoundary.invalid() }
                } while true
            case 91:
                index += 1
                if take(93) { return }
                repeat {
                    try value(depth: depth + 1)
                    if take(93) { return }
                    guard take(44) else { throw JSONBoundary.invalid() }
                } while true
            case 34: _ = try string(key: false)
            default:
                let start = index
                while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                guard index > start else { throw JSONBoundary.invalid() }
                // Typed decoding validates number/literal grammar and values.
            }
        }
    }
}
