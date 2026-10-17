import SwiftUI

struct WorkoutCorrectionView: View {
    let store: PhoneStore
    let sessionID: UUID
    private var session: WorkoutSession? { store.state.effectiveSession(sessionID) }
    var body: some View {
        LiftList {
            Section {
                Text(L10n.s("Correct a logged strength set")).font(LiftType.heading)
                Text(L10n.s("Correct the load or repetitions. Original values stay saved; reports update and older coach responses are flagged.")).font(.callout)
            }
            if let session {
                ForEach(session.executionExercises.filter { $0.kind == .strength }) { exercise in
                    Section(exercise.name) {
                        ForEach(session.entries.filter { $0.exerciseID == exercise.id }) { entry in
                            NavigationLink {
                                SetCorrectionEditor(store: store, sessionID: session.id, entry: entry, unit: session.plan.unit)
                            } label: {
                                MetricRow(title: L10n.s("Set \(entry.setNumber)"), value: "\(WorkoutSession.number(entry.weight)) \(session.plan.unit.rawValue) × \(entry.reps)")
                            }
                        }
                    }
                }
                if let summary = session.correctionSummary {
                    Section(L10n.s("Original values & corrections")) { Text(summary).font(.caption).textSelection(.enabled) }
                }
                Text(L10n.s("To undo a correction, enter the earlier values as a new correction. Timed activity events and imported history cannot be edited here.")).font(.caption).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle(L10n.s("Correct record")).navigationBarTitleDisplayMode(.inline)
    }
}

private struct SetCorrectionEditor: View {
    let store: PhoneStore
    let sessionID: UUID
    let entry: CompletedSet
    let unit: WeightUnit
    @Environment(\.dismiss) private var dismiss
    // Intentional draft snapshot: saving checks the original values still match.
    @State private var weight: String
    @State private var reps: String
    @State private var reason = ""
    @State private var error: String?
    init(store: PhoneStore, sessionID: UUID, entry: CompletedSet, unit: WeightUnit) {
        self.store = store; self.sessionID = sessionID; self.entry = entry; self.unit = unit
        _weight = State(initialValue: String(entry.weight)); _reps = State(initialValue: String(entry.reps))
    }
    var body: some View {
        LiftForm {
            Section(L10n.s("Currently saved")) {
                Text("\(WorkoutSession.number(entry.weight)) \(unit.rawValue) × \(entry.reps)").font(LiftType.heading)
            }
            Section(L10n.s("Correct values")) {
                LabeledContent(unit.rawValue) {
                    TextField(unit.rawValue, text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .accessibilityLabel(L10n.s("Corrected load")).accessibilityIdentifier("correction.weight")
                }
                LabeledContent(L10n.s("Repetitions")) {
                    TextField(L10n.s("Repetitions"), text: $reps).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .accessibilityLabel(L10n.s("Corrected repetitions")).accessibilityIdentifier("correction.reps")
                }
                TextField(L10n.s("Reason, optional"), text: $reason, axis: .vertical).lineLimit(2...4)
                Text(L10n.s("Only confirmed values change. No new exercise time or rest measurement is created.")).font(.caption).foregroundStyle(.secondary)
            }
            if let error { Section { Text(error).foregroundStyle(.secondary) } }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle(L10n.s("Set \(entry.setNumber)")).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(L10n.s("Save correction")) {
                    do {
                        guard let value = Double(weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")),
                              let count = Int(reps.trimmingCharacters(in: .whitespaces)) else {
                            throw WorkoutError.invalidInput(L10n.s("Use weight 0–1000 and 1–200 repetitions."))
                        }
                        try store.correctSet(sessionID: sessionID, setID: entry.id, expectedWeight: entry.weight, expectedReps: entry.reps,
                            weight: value, reps: count, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.s("Corrected entry") : reason)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(QuietButtonStyle(prominent: true)).padding(.horizontal, 24).padding(.vertical, 12).background(.black)
                    .accessibilityIdentifier("correction.save")
            }
    }
}
