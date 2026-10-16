import Foundation

public enum ReviewStatus: String, Codable, Sendable { case queued, running, received, cancelled, failed }
public struct ReviewJob: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID // completed session ID; durable deduplication key
    public var status: ReviewStatus
    public var attemptID: UUID?
    public var startedAt: Date?
    public var detail: String?
    public var notified: Bool?
    public init(sessionID: UUID) { id = sessionID; status = .queued }
}
public struct ReviewTicket: Equatable, Sendable { public let sessionID: UUID; public let attemptID: UUID }

extension PhoneState {
    public var reviewQueue: [ReviewJob] { reviewJobs ?? [] }
    public mutating func queueReview(for sessionID: UUID) {
        guard sessions.contains(where: { $0.id == sessionID }), !reviewQueue.contains(where: { $0.id == sessionID }) else { return }
        var jobs = reviewQueue; jobs.append(ReviewJob(sessionID: sessionID)); reviewJobs = jobs
    }
    public mutating func beginReview(sessionID: UUID? = nil, now: Date = Date()) throws -> ReviewTicket {
        guard review == nil else { throw WorkoutError.invalidState(L10n.s("Review or discard the existing proposal before requesting another review.")) }
        var jobs = reviewQueue
        if let active = jobs.first(where: { $0.status == .running }) {
            guard let started = active.startedAt, now.timeIntervalSince(started) >= 600 else {
                throw WorkoutError.invalidState(L10n.s("A review is already running. Cancel it in Little Lift before retrying."))
            }
            if let i = jobs.firstIndex(where: { $0.id == active.id }) { jobs[i].status = .failed; jobs[i].detail = L10n.s("No model result arrived within 10 minutes. Retry explicitly.") }
        }
        let id: UUID
        if let sessionID { id = sessionID }
        else if let queued = jobs.first(where: { $0.status == .queued }) { id = queued.id }
        else if let latest = sessions.first { id = latest.id }
        else { throw WorkoutError.invalidState(L10n.s("Complete a workout first, or share your training profile with your existing chat.")) }
        guard sessions.contains(where: { $0.id == id }) else { throw WorkoutError.invalidInput(L10n.s("The workout for this review is unavailable.")) }
        if !jobs.contains(where: { $0.id == id }) { jobs.append(ReviewJob(sessionID: id)) }
        let i = jobs.firstIndex { $0.id == id }!
        guard jobs[i].status != .received else { throw WorkoutError.invalidState(L10n.s("This workout already has a saved review. Share its report for a follow-up in your existing chat.")) }
        let attempt = UUID(); jobs[i].status = .running; jobs[i].attemptID = attempt; jobs[i].startedAt = now; jobs[i].detail = nil
        reviewJobs = jobs
        return ReviewTicket(sessionID: id, attemptID: attempt)
    }
    public mutating func endReview(_ id: UUID, cancelled: Bool, detail: String) throws {
        var jobs = reviewQueue
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].status != .received else { throw WorkoutError.invalidState(L10n.s("No unfinished review to change.")) }
        jobs[i].status = cancelled ? .cancelled : .failed; jobs[i].detail = String(detail.prefix(500)); reviewJobs = jobs
    }
    /// Replays of the same successful result are harmless. Stale/cancelled attempts
    /// cannot overwrite a newer proposal, even after a delayed model response.
    public mutating func receiveReview(_ text: String) throws {
        guard text.utf8.count <= 64_000 else { throw WorkoutError.invalidInput(L10n.s("The review is too large.")) }
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = plain.hasPrefix("```") ? plain.components(separatedBy: .newlines).dropFirst().dropLast().joined(separator: "\n") : plain
        let object = (try? JSONSerialization.jsonObject(with: Data(stripped.utf8))) as? [String: Any]
        let sessionID = (object?["reviewSessionID"] as? String).flatMap(UUID.init(uuidString:))
        let attemptID = (object?["reviewAttemptID"] as? String).flatMap(UUID.init(uuidString:))
        if object?["reviewSessionID"] != nil || object?["reviewAttemptID"] != nil {
            guard sessionID != nil && attemptID != nil else { throw WorkoutError.invalidInput(L10n.s("Review receipt identifiers must both be valid UUIDs from Prepare Workout Review.")) }
        }
        var jobs = reviewQueue
        if let sessionID, let attemptID {
            guard let i = jobs.firstIndex(where: { $0.id == sessionID }), jobs[i].attemptID == attemptID else { throw WorkoutError.invalidInput(L10n.s("This review belongs to an unknown or older attempt. It was not applied.")) }
            if jobs[i].status == .received { return }
            guard jobs[i].status == .running else { throw WorkoutError.invalidState(L10n.s("This review was cancelled or failed. Start a new attempt explicitly.")) }
            guard review == nil else { throw WorkoutError.invalidState(L10n.s("Review the existing proposal before saving another.")) }
            let proposal = try PlanImport.parseReview(text)
            try propose(proposal); jobs[i].status = .received; jobs[i].detail = L10n.s("Saved for explicit acceptance."); reviewJobs = jobs
        } else {
            guard sessionID == nil && attemptID == nil, !jobs.contains(where: { $0.status == .running }) else { throw WorkoutError.invalidInput(L10n.s("Return both reviewSessionID and reviewAttemptID exactly as supplied by Prepare Workout Review.")) }
            guard review == nil else { throw WorkoutError.invalidState(L10n.s("Review the current proposal first.")) }
            try propose(PlanImport.parseReview(text))
        }
    }
    public func prompt(for ticket: ReviewTicket) throws -> String {
        guard let session = sessions.first(where: { $0.id == ticket.sessionID }) else { throw WorkoutError.invalidInput(L10n.s("Review workout missing.")) }
        return """
        \(PlanImport.reviewPrompt(profile: contextExport(), sessions: [session]))
        REVIEW RECEIPT — include these two additional top-level JSON fields exactly, alongside analysis and plan:
        "reviewSessionID": "\(ticket.sessionID.uuidString)",
        "reviewAttemptID": "\(ticket.attemptID.uuidString)"
        Write analysis in \(comfort?.language == "es" ? "Spanish" : "the user’s preferred language"). Keep JSON keys and stable identifiers unchanged.
        Review this specific completed workout, including delayed delivery. A failed or cancelled attempt will not be applied. Never claim access to an existing chat.
        """
    }
}

/// Shared touch/gesture deduplication. A rapid second action cannot log another set,
/// including zero-rest workouts. Durable Log timestamps also protect relaunch.
public enum LogActionGuard {
    public static func allows(session: WorkoutSession?, presentedSheet: Bool, now: Date = Date()) -> Bool {
        guard !presentedSheet, let session, session.phase == .active else { return false }
        return session.entries.last.map { now.timeIntervalSince($0.completedAt) >= 2 } ?? true
    }
}
