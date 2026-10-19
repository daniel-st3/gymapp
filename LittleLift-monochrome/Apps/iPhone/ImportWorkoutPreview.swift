import SwiftUI

/// A deliberately small acceptance screen. Advanced routine editing remains
/// available separately; an import does not require a trip into every exercise.
struct ImportWorkoutPreview: View {
    let store: PhoneStore
    let finished: () -> Void
    let useToday: Bool
    let chatReply: ChatWorkoutReply?
    @State private var draft: WorkoutDraft
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var dynamicType
    init(store: PhoneStore, initial: WorkoutDraft, useToday: Bool = true, chatReply: ChatWorkoutReply? = nil, finished: @escaping () -> Void) {
        self.store = store; self.finished = finished; self.useToday = useToday; self.chatReply = chatReply
        _draft = State(initialValue: initial) // isolated, intentional review snapshot
    }
    private var plan: WorkoutPlan? { try? draft.validated() }
    private var validationError: String? {
        do { _ = try draft.validated(); return nil } catch { return error.localizedDescription }
    }
    private var missingRest: Bool { draft.exercises.contains { $0.kind == .strength && $0.rest.isEmpty } }
    private var missingUnit: Bool { draft.exercises.contains { $0.kind == .strength && $0.unit.isEmpty } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TextField(L10n.s("Workout name"), text: $draft.title).font(LiftType.title).accessibilityLabel(L10n.s("Workout name"))
                Text(L10n.s("Check the exercises against your chat. Nothing changes until you use this workout."))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let chatReply {
                    Text(chatReply.review.analysis).font(.subheadline).textSelection(.enabled)
                    Label(L10n.s("Reply linked to your copied message"), systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                }
                if !useToday { Text(L10n.s("Save for later. Today and any active workout stay as they are.")).font(.caption).foregroundStyle(.secondary) }
                if missingUnit || missingRest {
                    LiftSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.s("Not in the message? Choose once.")).font(.subheadline)
                            if missingUnit {
                                HStack {
                                    Text(L10n.s("Load unit")).font(.caption)
                                    ForEach(WeightUnit.allCases, id: \.self) { unit in
                                        Button(unit.rawValue) { draft.fillMissingUnit(unit) }.buttonStyle(QuietButtonStyle())
                                    }
                                }
                            }
                            if missingRest {
                                Text(L10n.s("Rest for exercises without a rest target")).font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    ForEach([60, 90, 120], id: \.self) { seconds in
                                        Button("\(seconds)s") { try? draft.fillMissingRest(seconds) }.buttonStyle(QuietButtonStyle())
                                    }
                                }
                            }
                        }.padding(16)
                    }
                }
                ForEach($draft.exercises) { $exercise in
                    LiftSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField(L10n.s("Exercise name"), text: $exercise.name).font(.body).accessibilityLabel(L10n.s("Exercise name"))
                            if exercise.kind == .strength {
                                let fieldsLayout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                                fieldsLayout {
                                    input(L10n.s("Sets"), text: $exercise.sets)
                                    input(L10n.s("Repetitions"), text: $exercise.reps)
                                    input(L10n.s("Rest (s)"), text: $exercise.rest)
                                }
                                if exercise.reps.isEmpty, !exercise.repetitionChoices.isEmpty {
                                    Text(L10n.s("Your coach gave a range. Choose today’s target:")).font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        ForEach(exercise.repetitionChoices, id: \.self) { number in
                                            Button(String(number)) { exercise.reps = String(number) }.buttonStyle(QuietButtonStyle())
                                        }
                                    }
                                }
                                if exercise.chooseLoadOnWatch {
                                    Label(L10n.s("Choose the actual load on Watch"), systemImage: "applewatch").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    HStack {
                                        input(L10n.s("Load"), text: $exercise.weight)
                                        Picker(L10n.s("Unit"), selection: $exercise.unit) {
                                            Text(L10n.s("Choose")).tag(""); Text("kg").tag("kg"); Text("lb").tag("lb")
                                        }.tint(.white)
                                    }
                                }
                            } else {
                                Text((try? exercise.exercise())?.activity?.summary ?? L10n.s("Choose an activity type and its details.")).font(.caption).foregroundStyle(.secondary)
                            }
                            NavigationLink(L10n.s("Edit details or remove")) {
                                DraftExerciseEditorView(exercise: $exercise) { draft.removeExercise(exercise.id) }
                            }.font(.caption).frame(minHeight: 44)
                        }.padding(16)
                    }
                }
                Button { var row = DraftExercise(); row.kind = .strength; row.chooseLoadOnWatch = true; draft.exercises.append(row) } label: {
                    Label(L10n.s("Add exercise"), systemImage: "plus")
                }.frame(minHeight: 44).disabled(draft.exercises.count >= 50)
                if let plan {
                    if !plan.observationRequests.isEmpty { ObservationCollectionView(plan: plan) }
                    if plan.exercises.contains(where: { !($0.alternatives ?? []).isEmpty }) {
                        DisclosureGroup(L10n.s("Collection & approved alternatives")) {
                            ForEach(plan.exercises) { exercise in
                                ForEach(exercise.alternatives ?? []) { alternative in
                                    Text(alternative.name + " · " + "\(alternative.reps) × \(WorkoutSession.number(alternative.weight)) \(alternative.unit.rawValue)").font(.caption)
                                }
                            }
                        }
                    }
                }
                DisclosureGroup(L10n.s("See original text")) {
                    Text(draft.source).font(.caption).textSelection(.enabled)
                    ForEach(draft.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }.font(.subheadline)
                if let message = error ?? validationError { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }.padding(20)
        }.scrollDismissesKeyboard(.interactively).background(.black).buttonStyle(.plain)
            .navigationTitle(L10n.s("Check your workout")).navigationBarTitleDisplayMode(.inline)
            .alert(L10n.s("Needs attention"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(L10n.s("OK")) { error = nil }
            } message: { Text(error ?? "") }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 6) {
                    if plan == nil {
                        Text(L10n.s("Complete the empty fields above to continue.")).font(.caption).foregroundStyle(.secondary)
                    }
                    Button(useToday ? L10n.s("Use this workout · send to Watch") : L10n.s("Save routine")) {
                        do {
                            let plan = try draft.validated()
                            if let chatReply { try store.acceptChatReply(chatReply, editedPlan: plan, useToday: useToday) }
                            else { try store.saveWorkout(plan, useToday: useToday) }
                            finished()
                        }
                        catch { self.error = error.localizedDescription }
                    }.buttonStyle(QuietButtonStyle(prominent: true)).disabled(plan == nil)
                }.padding(.horizontal, 20).padding(.vertical, 10).background(.black)
            }
    }
    private func input(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("—", text: text).keyboardType(.decimalPad).font(.body.monospacedDigit())
                .frame(minHeight: 44).accessibilityLabel(title)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ImportRoutineChoices: View {
    let store: PhoneStore
    let finished: () -> Void
    var body: some View {
        LiftList {
            ForEach(store.state.routineLibrary) { routine in
                NavigationLink { WorkoutChoicePreview(store: store, routineID: routine.id, finished: finished) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(routine.plan.title)
                        Text(LiftCopy.workoutSummary(routine.plan)).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
        }.navigationTitle(L10n.s("Saved workouts")).scrollContentBackground(.hidden).background(.black)
    }
}
