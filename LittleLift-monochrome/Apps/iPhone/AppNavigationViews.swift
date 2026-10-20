import SwiftUI

/// Daily actions stay on Train. Setup and analysis have stable, named destinations.
struct TodayWorkoutDetailView: View {
    let store: PhoneStore
    var body: some View {
        ScrollView {
            if let plan = store.state.plan {
                VStack(alignment: .leading, spacing: 24) {
                    LiftPageHeading(title: plan.title, detail: LiftCopy.workoutSummary(plan))
                    LiftSurface {
                        ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                            LiftExerciseRow(exercise: exercise, unit: plan.unit, number: index + 1).padding(18)
                            if index < plan.exercises.count - 1 { Divider().padding(.horizontal, 18) }
                        }
                    }
                    NavigationLink { TimePlanningView(store: store) } label: {
                        LiftSurface { LiftMenuRow(title: L10n.s("Available time"), symbol: "clock", detail: L10n.s("Set a duration or finish time")) }
                    }
                    NavigationLink {
                        ScrollView { ObservationCollectionView(plan: plan).padding(24) }
                            .background(.black).navigationTitle(L10n.s("Coach observations")).navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LiftSurface { LiftMenuRow(title: L10n.s("Coach observations"), symbol: "text.bubble", detail: L10n.s("See what this workout collects")) }
                    }
                }.padding(24)
            }
        }.background(.black).buttonStyle(.plain)
            .navigationTitle(L10n.s("Saved workout")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let plan = store.state.plan {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(L10n.s("Edit")) {
                            WorkoutEditorView(store: store, initial: WorkoutDraft(plan: plan),
                                routineID: store.state.routineLibrary.first(where: { $0.plan.id == plan.id })?.id, useToday: true)
                        }.accessibilityIdentifier("train.edit")
                    }
                }
            }
    }
}

struct TrainingPreferencesHub: View {
    let store: PhoneStore
    var body: some View {
        LiftList {
            NavigationLink { ComfortSettingsView(store: store) } label: { LiftLabel(L10n.s("Language & feedback"), "slider.horizontal.3") }
            NavigationLink { TrainingProfileView(store: store) } label: { LiftLabel(L10n.s("Training profile"), "person.crop.circle") }
            NavigationLink { WatchPreferencesView(store: store) } label: { LiftLabel(L10n.s("Watch controls"), "applewatch") }
            NavigationLink { WeeklyHabitView(store: store) } label: { LiftLabel(L10n.s("Weekly goal"), "calendar") }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle(L10n.s("Preferences")).navigationBarTitleDisplayMode(.inline)
    }
}

struct TrainingDataHub: View {
    let store: PhoneStore
    var body: some View {
        LiftList {
            NavigationLink { WorkoutBackupView(store: store) } label: { LiftLabel(L10n.s("Backups"), "externaldrive") }
            NavigationLink { HistoryImportView(store: store) } label: { LiftLabel(L10n.s("Import past workouts"), "square.and.arrow.down") }
            NavigationLink { CoachContextView(store: store) } label: { LiftLabel(L10n.s("Sharing preferences"), "square.and.arrow.up") }
            NavigationLink { DataInformationView(store: store) } label: { LiftLabel(L10n.s("Data & connection"), "lock.shield") }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle(L10n.s("My data")).navigationBarTitleDisplayMode(.inline)
    }
}

struct TrainingHelpHub: View {
    let store: PhoneStore
    var body: some View {
        LiftList {
            NavigationLink { GettingStartedView(store: store) } label: { LiftLabel(L10n.s("Start here"), "play.circle") }
            NavigationLink { ExerciseHelpView() } label: { LiftLabel(L10n.s("Exercise guide"), "figure.strengthtraining.traditional") }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle(L10n.s("Help")).navigationBarTitleDisplayMode(.inline)
    }
}

struct TrainingExtrasHub: View {
    let store: PhoneStore
    var body: some View {
        LiftList {
            Section {
                NavigationLink { CoachingSettingsView(store: store) } label: { LiftLabel(L10n.s("Review with Shortcuts"), "arrow.triangle.branch") }
                NavigationLink { ReviewQueueView(store: store) } label: { LiftLabel(L10n.s("Coach reviews"), "text.bubble") }
            } footer: { Text(L10n.s("Your existing chat stays in My gym chat. Shortcuts run a separate conversation.")) }
            Section {
                NavigationLink { MotionLibraryView(store: store) } label: { LiftLabel(L10n.s("Motion experiment"), "waveform.path") }
            } footer: { Text(L10n.s("Optional. Ordinary workout logging needs none of these tools.")) }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle(L10n.s("Optional tools")).navigationBarTitleDisplayMode(.inline)
    }
}
