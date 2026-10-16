import Foundation

/// Native .strings resources. Keys are stable English templates; arguments are
/// data and never looked up as instructions or translated exercise identities.
public enum L10n {
    public struct Value: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        var key: String
        var arguments: [String]
        public init(stringLiteral value: String) { key = value; arguments = [] }
        public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
        public struct StringInterpolation: StringInterpolationProtocol {
            var key = ""
            var arguments: [String] = []
            public init(literalCapacity: Int, interpolationCount: Int) {}
            public mutating func appendLiteral(_ value: String) { key += value }
            public mutating func appendInterpolation<T>(_ value: T) { key += "{\(arguments.count)}"; arguments.append(String(describing: value)) }
        }
    }
    public static var language: String { UserDefaults.standard.string(forKey: "littlelift.language") ?? Bundle.main.preferredLocalizations.first ?? "en" }
    public static func key(_ text: String) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return text }
        return bundle.localizedString(forKey: text, value: text, table: "Localizable")
    }
    public static func s(_ value: Value) -> String {
        // Substitute only template positions, never recursively substitute data.
        let format = key(value.key)
        var result = "", cursor = format.startIndex
        while cursor < format.endIndex {
            if format[cursor] == "{", let end = format[cursor...].firstIndex(of: "}"), let index = Int(format[format.index(after: cursor)..<end]), value.arguments.indices.contains(index) {
                result += value.arguments[index]; cursor = format.index(after: end)
            } else { result.append(format[cursor]); cursor = format.index(after: cursor) }
        }
        return result
    }
}
