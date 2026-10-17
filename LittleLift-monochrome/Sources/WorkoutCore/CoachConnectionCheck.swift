import Foundation

/// Separate from workout history, review jobs and proposals. This verifies the
/// return path, not coaching quality, background automation or chat continuity.
public struct CoachConnectionCheck: Codable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public var receivedAt: Date?
    public var cancelled: Bool
    public init(now: Date = Date()) { id = UUID(); startedAt = now; cancelled = false }
    public func validate() throws {
        guard InputBoundary.validDate(startedAt), receivedAt.map({ InputBoundary.validDate($0) && $0 >= startedAt && $0.timeIntervalSince(startedAt) < 600 }) ?? true else {
            throw WorkoutError.invalidInput(L10n.s("Invalid connection-check dates."))
        }
    }
    public func isWaiting(now: Date = Date()) -> Bool {
        !cancelled && receivedAt == nil && (0..<600).contains(now.timeIntervalSince(startedAt))
    }
    public var prompt: String { """
    Little Lift connection check. All data below is fictional. No personal profile or history is included.
    A generic strength set prescribed 10 repetitions at 20 kg. The person confirmed 8 repetitions at 20 kg.
    Return ONLY this JSON structure, replacing confirmedRepetitions with the confirmed count from the data. No markdown, medical advice or workout proposal.
    {"connectionCheckID":"\(id.uuidString)","confirmedRepetitions":8}
    This tests the selected model and Save Workout Review return path. It does not access an existing conversation.
    """ }
}

extension PhoneState {
    public mutating func beginConnectionCheck(now: Date = Date()) throws -> String {
        guard InputBoundary.validDate(now) else { throw WorkoutError.invalidInput(L10n.s("Invalid connection-check dates.")) }
        guard coachConnectionCheck?.isWaiting(now: now) != true else {
            throw WorkoutError.invalidState(L10n.s("A connection check is running. Cancel it or wait 10 minutes before retrying."))
        }
        let check = CoachConnectionCheck(now: now); coachConnectionCheck = check; return check.prompt
    }
    public mutating func cancelConnectionCheck() { coachConnectionCheck?.cancelled = true }
    /// Returns false for ordinary review JSON; malformed test receipts cannot
    /// fall through into plan import or the real-workout review queue.
    public mutating func receiveConnectionCheck(_ text: String, now: Date = Date()) throws -> Bool {
        let data = try PlanImport.jsonData(text)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard object?["connectionCheckID"] != nil else { return false }
        struct Response: Decodable { let connectionCheckID: UUID; let confirmedRepetitions: Int }
        guard Set(object?.keys.map { $0 } ?? []) == ["connectionCheckID", "confirmedRepetitions"],
              let response = try? JSONDecoder().decode(Response.self, from: data), response.confirmedRepetitions == 8,
              var check = coachConnectionCheck, response.connectionCheckID == check.id else {
            throw WorkoutError.invalidInput(L10n.s("This test response does not match the current connection check. Nothing was changed."))
        }
        if check.receivedAt != nil { return true } // successful duplicate is harmless
        guard check.isWaiting(now: now) else {
            throw WorkoutError.invalidState(L10n.s("This connection check expired or was cancelled. Run a new check explicitly."))
        }
        check.receivedAt = now; try check.validate(); coachConnectionCheck = check; return true
    }
}
