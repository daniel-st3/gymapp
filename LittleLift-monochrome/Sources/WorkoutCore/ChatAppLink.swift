import Foundation

/// A private conversation link is a navigation preference, not permission to
/// read the conversation. Shared snapshots and arbitrary URLs are not accepted.
public enum ChatAppLink {
    public static func destination(_ text: String) throws -> URL {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return URL(string: "https://chatgpt.com/open-app")! }
        guard value.utf8.count <= 512, let url = URLComponents(string: value),
              url.scheme?.lowercased() == "https",
              ["chatgpt.com", "chat.openai.com"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { throw invalid() }
        let parts = url.path.split(separator: "/")
        guard parts.count == 2, parts[0] == "c", let id = UUID(uuidString: String(parts[1])) else { throw invalid() }
        return URL(string: "https://chatgpt.com/c/\(id.uuidString.lowercased())")!
    }
    private static func invalid() -> WorkoutError {
        .invalidInput(L10n.s("Use the private chatgpt.com/c/… address of your conversation. A Share link is a public snapshot, not your existing chat."))
    }
}
