import SwiftUI

struct AdaptiveWorkoutView: View {
    let store: WatchStore
    @State private var confirmingOmissions = false
    @State private var future = false
    @State private var skipping = false
    @State private var alternative: ExerciseAlternative?
    var body: some View {
        List {
            if let session = store.state.session {
                if session.phase != .completed {
                    Section(L10n.s("Change exercise")) {
                        Button(L10n.s("Machine busy · do later")) { store.perform { try store.deferExercise() } }.disabled(session.remainingExercises.count < 2)
                        if let current = session.currentExercise,
                           let original = session.plan.exercises.first(where: { $0.id == session.originalID(for: current.id) }) {
                            ForEach(original.alternatives ?? []) { item in
                                Button(L10n.s("Use \(item.name)")) { alternative = item }
                                    .disabled(item.unit != session.plan.unit || session.entries.contains { session.originalID(for: $0.exerciseID) == original.id })
                            }
                            if original.alternatives?.isEmpty ?? true { Text(L10n.s("Add approved alternatives in iPhone Routines.")).watchText(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Section {
                        Button(L10n.s("Skip remaining exercise…")) { skipping = true }.disabled(session.activityTimer != nil)
                        Text(L10n.s("If you prefer to stop or feel discomfort, omit it. No substitute is assumed safe.")).watchText(.caption).foregroundStyle(.secondary)
                    }
                    Section(L10n.s("Choose next")) {
                        ForEach(session.remainingExercises) { exercise in
                            Button(exercise.name) { store.perform { try store.chooseNext(session.originalID(for: exercise.id)) }; store.presentedSheet = nil }
                                .disabled(session.activityTimer != nil || exercise.id == session.currentExercise?.id)
                        }
                        Text(L10n.s("Pending work stays in the workout.")).watchText(.caption).foregroundStyle(.secondary)
                    }
                    Section(L10n.s("Shorter remainder")) {
                        let candidates = optional(session)
                        if candidates.isEmpty { Text(L10n.s("No optional work to remove for your time target.")).watchText(.secondary) }
                        else {
                            ForEach(candidates) { Text($0.name).watchText(.secondary) }
                            Button(L10n.s("Review shorter workout")) { confirmingOmissions = true }
                        }
                        Button(L10n.s("Undo adjustment")) { store.perform { try store.reverseAdjustment() } }
                            .disabled(session.previousConfiguration == nil || session.adjustmentEntryCount != session.loggedWorkCount)
                        Text(L10n.s("Undo before your next set.")).watchText(.secondary).foregroundStyle(.secondary)
                    }
                }
                Section(L10n.s("Estimated finish")) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(WorkoutPace.remaining(session, history: store.state.recent, now: context.date).text).watchText(.secondary)
                    }
                    if let deadline = session.plan.timeBudget?.deadline(start: session.startedAt) { Text(L10n.s("Aim: \(deadline.formatted(date: .omitted, time: .shortened))")).watchText(.secondary) }
                    Text(L10n.s("Based on logging pace, not measured rest.")).watchText(.secondary).foregroundStyle(.secondary)
                }
                if let changes = session.adjustments, let last = changes.last { Section(L10n.s("Latest change")) { Text(last.detail).watchText(.caption) } }
            }
        }.navigationTitle(L10n.s("Adjust"))
            .confirmationDialog(L10n.s("Omit approved optional work?"), isPresented: $confirmingOmissions, titleVisibility: .visible) {
                Button(L10n.s("Omit listed exercises")) {
                    if let session = store.state.session { store.perform { try store.omitOptional(optional(session).map { session.originalID(for: $0.id) }) } }
                }
            } message: { Text(L10n.s("Only the listed unstarted optional work is removed. No load, rep or required rest changes. Reverse before the next Log tap.")) }
            .confirmationDialog(L10n.s("Skip the remaining work? Logged sets stay saved."), isPresented: $skipping, titleVisibility: .visible) {
                Button(L10n.s("Skip exercise")) { store.perform { try store.skipExercise() }; store.presentedSheet = nil }
            }
            .sheet(item: $alternative) { item in
                WatchPage {
                    ScrollView { VStack(alignment: .leading, spacing: 8) {
                        Text(item.name)
                        Text(L10n.s("\(WorkoutSession.number(item.weight)) \(item.unit.rawValue) × \(item.reps) · \(item.restSeconds)s rest")).watchText(.secondary)
                        Toggle(L10n.s("Propose for future review"), isOn: $future)
                        Text(L10n.s("Approved alternative. Coach observations for the original won’t transfer.")).watchText(.secondary).foregroundStyle(.secondary)
                    } }
                } actions: {
                    Button(L10n.s("Use alternative")) { store.perform { try store.substitute(item.id, future: future) }; alternative = nil }.buttonStyle(QuietButtonStyle())
                }
            }
    }
    private func optional(_ session: WorkoutSession) -> [ExercisePlan] {
        WorkoutPace.shorterProposal(session, history: store.state.recent)
    }
}
