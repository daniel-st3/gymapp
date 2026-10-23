import SwiftUI

/// A deliberately small acceptance screen. Advanced routine editing remains
/// available separately; an import does not require a trip into every exercise.
struct ImportWorkoutPreview: View {
    let store: PhoneStore
    let finished: () -> Void
    let useToday: Bool
    let chatReply: ChatWorkoutReply?
    @State private var draft: WorkoutDraft
    @State private var expandedRows: Set<UUID>
    @State private var error: String?
    @FocusState private var focusedField: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    init(store: PhoneStore, initial: WorkoutDraft, useToday: Bool = true, chatReply: ChatWorkoutReply? = nil, finished: @escaping () -> Void) {
        self.store = store; self.finished = finished; self.useToday = useToday; self.chatReply = chatReply
        _draft = State(initialValue: initial) // isolated, intentional review snapshot
        _expandedRows = State(initialValue: Set(initial.exercises.filter { !$0.fieldsToReview.isEmpty }.map(\.id)))
    }
    private var plan: WorkoutPlan? { try? draft.validated() }
    private var validationError: String? {
        do { _ = try draft.validated(); return nil } catch { return error.localizedDescription }
    }
    private var issues: [WorkoutDraftIssue] { draft.reviewIssues }
    private var missingRest: Bool { draft.exercises.contains { $0.kind == .strength && $0.rest.isEmpty } }
    private var missingUnit: Bool { draft.exercises.contains { $0.kind == .strength && $0.unit.isEmpty } }
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TextField(L10n.s("Workout name"), text: $draft.title).font(LiftType.title).accessibilityLabel(L10n.s("Workout name")).focused($focusedField, equals: "title").id("title")
                Text(L10n.s("Check the exercises against your chat. Nothing changes until you use this workout."))
                    .font(.subheadline).foregroundStyle(.secondary)
                if useToday {
                    Text(L10n.s("The workout date is recorded automatically when you start on Watch.")).font(.caption).foregroundStyle(.secondary)
                }
                if !issues.isEmpty {
                    LiftSurface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.s("To finish · \(issues.count)")).font(.subheadline)
                            ForEach(issues) { issue in
                                Button { reveal(issue, proxy: proxy) } label: {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(issue.title).font(.subheadline)
                                            Text(issue.message).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 8)
                                        Image(systemName: "arrow.down").font(.caption)
                                    }.frame(minHeight: 44).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }.padding(16)
                    }.id("workout").accessibilityIdentifier("import.remaining")
                }
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
                                        Button(unit == .lb ? "lb · lbs" : "kg") { draft.fillMissingUnit(unit) }.buttonStyle(QuietButtonStyle())
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
                            if !expandedRows.contains(exercise.id), let item = try? exercise.exercise() {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(exercise.name).font(.body)
                                        Text(item.prescription(unit: WeightUnit(rawValue: exercise.unit) ?? .kg))
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 12)
                                    Button(L10n.s("Edit")) { expandedRows.insert(exercise.id) }.frame(minWidth: 44, minHeight: 44)
                                }
                            } else {
                            TextField(L10n.s("Exercise name"), text: $exercise.name).font(.body).accessibilityLabel(L10n.s("Exercise name"))
                                .focused($focusedField, equals: exercise.id.uuidString + ".name")
                            if let issue = issues.first(where: { $0.exerciseID == exercise.id }) {
                                Label(issue.message, systemImage: "pencil.circle").font(.caption).foregroundStyle(.secondary)
                            }
                            if exercise.kind == nil {
                                Picker(L10n.s("Activity type"), selection: $exercise.kind) {
                                    Text(L10n.s("Choose type")).tag(ActivityKind?.none)
                                    ForEach(ActivityKind.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                                }
                                Text(L10n.s("This exercise was only partly read. Check its source and complete the missing targets."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if exercise.kind == .strength || (exercise.kind == nil && !exercise.sets.isEmpty && !exercise.reps.isEmpty) {
                                let fieldsLayout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                                fieldsLayout {
                                    input(L10n.s("Sets"), text: $exercise.sets, id: exercise.id.uuidString + ".sets", invalid: exercise.fieldsToReview.contains(L10n.s("Sets")))
                                    input(L10n.s("Repetitions"), text: $exercise.reps, id: exercise.id.uuidString + ".reps", invalid: exercise.fieldsToReview.contains(L10n.s("Repetitions")))
                                    input(L10n.s("Rest (s)"), text: $exercise.rest, id: exercise.id.uuidString + ".rest", invalid: exercise.fieldsToReview.contains(L10n.s("Rest · seconds")))
                                }
                                if exercise.reps.isEmpty, !exercise.repetitionChoices.isEmpty {
                                    Text(L10n.s("Your coach gave a range. Choose today’s target:")).font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        ForEach(exercise.repetitionChoices, id: \.self) { number in
                                            Button(String(number)) { exercise.reps = String(number) }.buttonStyle(QuietButtonStyle())
                                        }
                                    }
                                }
                                HStack(alignment: .bottom) {
                                    input(L10n.s("Load"), text: Binding(get: { exercise.weight }, set: { value in
                                        exercise.weight = value
                                        exercise.chooseLoadOnWatch = value.trimmingCharacters(in: .whitespaces).isEmpty && exercise.convention != "bodyweight"
                                    }), id: exercise.id.uuidString + ".weight", invalid: exercise.fieldsToReview.contains(L10n.s("Load")))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L10n.s("Unit")).font(.caption).foregroundStyle(.secondary)
                                        Picker(L10n.s("Unit"), selection: $exercise.unit) {
                                            Text(L10n.s("Choose")).tag(""); Text("kg").tag("kg"); Text("lb · lbs").tag("lb")
                                        }.tint(.white).frame(minHeight: 44)
                                    }
                                }
                                if exercise.chooseLoadOnWatch {
                                    Text(L10n.s("No load target. Enter it here, or choose the actual load on Watch.")).font(.caption).foregroundStyle(.secondary)
                                } else if !exercise.weight.isEmpty && exercise.convention != "bodyweight" {
                                    Button(L10n.s("Choose load on Watch instead")) { exercise.weight = ""; exercise.chooseLoadOnWatch = true }
                                        .font(.caption).frame(minHeight: 44)
                                }
                            } else {
                                Text((try? exercise.exercise())?.activity?.summary ?? L10n.s("Choose an activity type and its details.")).font(.caption).foregroundStyle(.secondary)
                            }
                            NavigationLink(L10n.s("Edit details or remove")) {
                                DraftExerciseEditorView(exercise: $exercise) { draft.removeExercise(exercise.id) }
                            }.font(.caption).frame(minHeight: 44)
                            }
                        }.padding(16)
                    }.id(exercise.id.uuidString)
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
            .toolbar { ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.s("Done")) { focusedField = nil }
            } }
            .onChange(of: draft) { error = nil }
            .alert(L10n.s("Needs attention"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(L10n.s("OK")) { error = nil }
            } message: { Text(error ?? "") }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 6) {
                    if let issue = issues.first {
                        Text(issue.title + " · " + issue.message)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Button(plan == nil ? L10n.s("Review what’s missing") : (useToday ? L10n.s("Use this workout") : L10n.s("Save routine"))) {
                        focusedField = nil
                        if let issue = issues.first { reveal(issue, proxy: proxy); return }
                        do {
                            let plan = try draft.validated()
                            if let chatReply { try store.acceptChatReply(chatReply, editedPlan: plan, useToday: useToday) }
                            else { try store.saveWorkout(plan, useToday: useToday) }
                            finished()
                        }
                        catch { self.error = error.localizedDescription }
                    }.buttonStyle(QuietButtonStyle(prominent: true)).accessibilityIdentifier("import.accept")
                    if useToday { Text(L10n.s("Sends to Watch. Open Little Lift there and tap Start.")).font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal, 20).padding(.vertical, 10).background(.black)
            }
        }
    }
    private func reveal(_ issue: WorkoutDraftIssue, proxy: ScrollViewProxy) {
        focusedField = nil
        if let id = issue.exerciseID { expandedRows.insert(id) }
        else if issue.id == "workout" { expandedRows.formUnion(draft.exercises.map(\.id)) }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(issue.id, anchor: .top) }
    }
    private func input(_ title: String, text: Binding<String>, id: String, invalid: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title == L10n.s("Load") ? L10n.s("On Watch") : "—", text: text).keyboardType(.decimalPad).font(.body.monospacedDigit())
                .focused($focusedField, equals: id)
                .padding(.horizontal, 10).frame(minHeight: 44)
                .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(invalid ? 0.6 : 0.12), lineWidth: 1))
                .accessibilityLabel(title).accessibilityIdentifier("import.field." + id)
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
