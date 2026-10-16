import Foundation

/// Stores persist their candidate state BEFORE returning a response to the transport.
/// A failed disk write must never produce a receipt.
public enum SyncLogic {
    public static func snapshot(from state: PhoneState, acknowledging id: UUID? = nil, now: Date = Date()) -> PhoneSnapshot {
        var ids = Array(state.sessions.prefix(200).map(\.id))
        if let id, !ids.contains(id) { ids.append(id) }
        return PhoneSnapshot(plan: state.plan, acknowledged: ids, issuedAt: now, doubleTapEnabled: state.doubleTapEnabled, motionOptIn: state.motionOptIn, motionExercise: state.motionExercise, comfort: state.comfort)
    }

    public static func phoneReply(to message: SyncMessage, state: inout PhoneState, now: Date = Date()) throws -> SyncMessage? {
        switch message {
        case .requestSnapshot:
            return .snapshot(snapshot(from: state, now: now))
        case .completed(let workout):
            try state.receive(workout)
            return .snapshot(snapshot(from: state, acknowledging: workout.id, now: now))
        case .snapshot, .planReceived:
            return nil
        }
    }

    public static func watchReply(to snapshot: PhoneSnapshot, state: inout WatchState) throws -> SyncMessage? {
        try validate(snapshot)
        if let plan = snapshot.plan { try plan.validate() }
        state.acknowledge(snapshot.acknowledged)
        // Out-of-order receipts remain useful; an older plan must not replace a newer one.
        if state.lastSnapshotDate.map({ snapshot.issuedAt >= $0 }) ?? true {
            if state.comfort != snapshot.comfort, let master = snapshot.comfort?.haptics { state.haptics = master }
            state.comfort = snapshot.comfort
            state.motionOptIn = snapshot.motionOptIn
            state.motionExercise = snapshot.motionExercise
            state.doubleTapEnabled = snapshot.doubleTapEnabled
            state.plan = snapshot.plan
            state.lastSnapshotDate = snapshot.issuedAt
        }
        return state.plan.map { .planReceived($0.id) }
    }

    public static func validate(_ snapshot: PhoneSnapshot) throws {
        guard snapshot.acknowledged.count <= 201,
              Set(snapshot.acknowledged).count == snapshot.acknowledged.count,
              InputBoundary.validDate(snapshot.issuedAt) else {
            throw WorkoutError.invalidInput(L10n.s("The received sync receipt is invalid. Saved workouts were preserved."))
        }
        try snapshot.comfort?.validate()
        try snapshot.plan?.validate()
    }
}
