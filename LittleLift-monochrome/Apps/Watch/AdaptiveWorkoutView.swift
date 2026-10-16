import SwiftUI

struct AdaptiveWorkoutView: View {
    let store: WatchStore
    @State private var confirmingOmissions = false
    @State private var alternative: ExerciseAlternative?
    var body: some View {
        List {
            if let session = store.state.session {
                Section("Estimated finish") {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(WorkoutPace.remaining(session, history: store.state.recent, now: context.date).text).watchText(.secondary)
                    }
                    if let deadline = session.plan.timeBudget?.deadline(start: session.startedAt) { Text("Aim: \(deadline.formatted(date: .omitted, time: .shortened))").watchText(.secondary) }
                    Text("Based on logging pace, not measured rest.").watchText(.secondary).foregroundStyle(.secondary)
                }
                if session.phase != .completed {
                    Section("Busy machine") {
                        Button("Do this later") { store.perform { try store.deferExercise() } }.disabled(session.remainingExercises.count < 2)
                        if let current = session.currentExercise,
                           let original = session.plan.exercises.first(where: { $0.id == session.originalID(for: current.id) }) {
                            ForEach(original.alternatives ?? []) { item in
                                Button("Use \(item.name)") { alternative = item }
                                    .disabled(item.unit != session.plan.unit || session.entries.contains { session.originalID(for: $0.exerciseID) == original.id })
                            }
                            if original.alternatives?.isEmpty ?? true { Text("Add approved alternatives in iPhone Routines.").watchText(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Section("Shorter remainder") {
                        let candidates = optional(session)
                        if candidates.isEmpty { Text("No optional work to remove for your time target.").watchText(.secondary) }
                        else {
                            ForEach(candidates) { Text($0.name).watchText(.secondary) }
                            Button("Review shorter workout") { confirmingOmissions = true }
                        }
                        Button("Undo adjustment") { store.perform { try store.reverseAdjustment() } }
                            .disabled(session.previousConfiguration == nil || session.adjustmentEntryCount != session.entries.count)
                        Text("Undo before your next set.").watchText(.secondary).foregroundStyle(.secondary)
                    }
                }
                if let changes = session.adjustments, let last = changes.last { Section("Latest change") { Text(last.detail).watchText(.caption) } }
            }
        }.navigationTitle("Adjust")
            .confirmationDialog("Omit approved optional work?", isPresented: $confirmingOmissions, titleVisibility: .visible) {
                Button("Omit listed exercises") {
                    if let session = store.state.session { store.perform { try store.omitOptional(optional(session).map { session.originalID(for: $0.id) }) } }
                }
            } message: { Text("Only the listed unstarted optional work is removed. No load, rep or required rest changes. Reverse before the next Log tap.") }
            .sheet(item: $alternative) { item in
                WatchPage {
                    ScrollView { VStack(alignment: .leading, spacing: 8) {
                        Text(item.name)
                        Text("\(WorkoutSession.number(item.weight)) \(item.unit.rawValue) × \(item.reps) · \(item.restSeconds)s rest").watchText(.secondary)
                        Text("Approved alternative. Coach observations for the original won’t transfer.").watchText(.secondary).foregroundStyle(.secondary)
                    } }
                } actions: {
                    Button("Use alternative") { store.perform { try store.substitute(item.id) }; alternative = nil }.buttonStyle(QuietButtonStyle())
                }
            }
    }
    private func optional(_ session: WorkoutSession) -> [ExercisePlan] {
        WorkoutPace.shorterProposal(session, history: store.state.recent)
    }
}
