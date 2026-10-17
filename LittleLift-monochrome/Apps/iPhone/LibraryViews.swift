import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct SmartImportView: View {
    let store: PhoneStore
    init(store: PhoneStore, initialText: String = "") {
        self.store = store
        _text = State(initialValue: initialText)
    }
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var draft: WorkoutDraft?
    @State private var reviewing = false
    @State private var error: String?
    @State private var photo: PhotosPickerItem?
    @State private var importingFile = false
    @State private var busy = false
    @State private var extraction: Task<Void, Never>?
    @State private var extractionID = UUID()
    @State private var timeout: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    LiftPageHeading(title: L10n.s("Bring your workout"), detail: L10n.s("Paste text, read a screenshot or start from scratch. Review everything before saving."))
                    LiftSection(title: L10n.s("Paste a workout")) {
                        LiftSurface {
                            ZStack(alignment: .topLeading) {
                                if text.isEmpty {
                                    Text(L10n.s("Bench press · 3 × 8 · 40 kg\nRest 90 seconds"))
                                        .font(.callout).foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.top, 8)
                                        .accessibilityHidden(true)
                                }
                                TextEditor(text: $text).font(.callout).frame(minHeight: 130).scrollContentBackground(.hidden)
                                    .scrollDismissesKeyboard(.interactively).accessibilityLabel(L10n.s("Workout source text"))
                            }.padding(14)
                            Divider().padding(.horizontal, 18)
                            HStack {
                                PasteButton(payloadType: String.self) { text = $0.joined(separator: "\n") }
                                    .labelStyle(.iconOnly).buttonBorderShape(.capsule).accessibilityLabel(L10n.s("Paste workout"))
                                Spacer()
                                Text(L10n.s("Text or JSON")).font(.caption).foregroundStyle(.secondary)
                            }.padding(14)
                        }
                    }
                    LiftSection(title: L10n.s("Or choose a source")) {
                        LiftSurface {
                            PhotosPicker(selection: $photo, matching: .images) {
                                LiftMenuRow(title: L10n.s("Read a screenshot"), symbol: "photo", detail: L10n.s("Text recognition on this device"))
                            }
                            Divider().padding(.horizontal, 18)
                            Button { importingFile = true } label: { LiftMenuRow(title: L10n.s("Choose a file"), symbol: "doc") }
                            Divider().padding(.horizontal, 18)
                            Button { draft = WorkoutDraft(); draft?.exercises = [DraftExercise()]; reviewing = true } label: {
                                LiftMenuRow(title: L10n.s("Build a workout"), symbol: "square.and.pencil")
                            }
                        }
                    }
                    DisclosureGroup(L10n.s("More import options")) {
                        Button(L10n.s("Try Apple Intelligence")) { modelExtract() }.buttonStyle(QuietButtonStyle())
                            .disabled(text.isEmpty || busy || !LocalWorkoutExtraction.modelAvailable)
                        Text(LocalWorkoutExtraction.availability).font(.caption).foregroundStyle(.secondary)
                        ShareLink(item: PlanImport.coachingPrompt) { Label(L10n.s("Share coaching prompt"), systemImage: "square.and.arrow.up") }
                            .font(.subheadline).frame(minHeight: 44)
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.secondary).accessibilityLabel(L10n.s("Import needs attention. ") + error) }
                }.disabled(busy).padding(24)
                if busy {
                    HStack { ProgressView(L10n.s("Reading workout…")); Spacer(); Button(L10n.s("Cancel")) { cancelExtraction() }.frame(minHeight: 44) }
                        .padding(.horizontal, 24).padding(.bottom, 20)
                }
            }.buttonStyle(.plain).background(.black)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Button { parse() } label: { Label(L10n.s("Preview workout"), systemImage: "list.bullet.rectangle") }.buttonStyle(QuietButtonStyle(prominent: true)).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                        .padding(.horizontal, 20).padding(.vertical, 10).background(.black)
                }
                .navigationDestination(isPresented: $reviewing) {
                    if let draft { WorkoutEditorView(store: store, initial: draft, routineID: nil, useToday: true) { dismiss() } }
                }
                .navigationTitle(L10n.s("Import workout")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.s("Close")) { dismiss() } } }
                .onChange(of: text) { draft = nil; error = nil }
                .onChange(of: photo) { loadPhoto() }
                .onDisappear { cancelExtraction() }
                .fileImporter(isPresented: $importingFile, allowedContentTypes: [.json, .plainText, .image]) { result in
                    do {
                        let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 20_000_000 else { throw WorkoutError.invalidInput(L10n.s("Choose a file below 20 MB.")) }
                        let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
                        let data = try InputBoundary.read(url, maximumBytes: isImage ? 20_000_000 : 64_000)
                        if isImage { recognize(data) }
                        else { guard data.count <= 64_000, let value = String(data: data, encoding: .utf8) else { throw WorkoutError.invalidInput(L10n.s("Text imports must be UTF-8 and below 64 KB.")) }; text = value }
                    } catch { self.error = error.localizedDescription }
                }
        }.tint(.white).presentationBackground(.black)
    }
    private func parse() { do { draft = try SmartWorkoutImport.extract(text); error = nil; reviewing = true } catch { self.error = error.localizedDescription } }
    private enum ExtractionResult { case text(String), draft(WorkoutDraft) }

    private func cancelExtraction() {
        // Invalidate first: a non-cooperative OCR/model operation may finish
        // after cancellation and must never publish into a newer import.
        extractionID = UUID()
        extraction?.cancel(); timeout?.cancel()
        extraction = nil; timeout = nil; busy = false
    }
    private func extract(_ work: @escaping @MainActor () async throws -> ExtractionResult) {
        cancelExtraction()
        let id = UUID(); extractionID = id; busy = true; error = nil
        timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            guard extractionID == id, busy else { return }
            cancelExtraction()
            error = L10n.s("Reading took too long. Try again, paste workout text, or build it manually.")
        }
        extraction = Task { @MainActor in
            defer {
                if extractionID == id { timeout?.cancel(); timeout = nil; busy = false; extraction = nil }
            }
            do {
                let result = try await work()
                try Task.checkCancellation()
                guard extractionID == id else { return }
                switch result {
                case .text(let value): text = value
                case .draft(let value): draft = value; reviewing = true
                }
            } catch is CancellationError {
            } catch {
                guard extractionID == id, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
    private func modelExtract() {
        let source = text
        extract { .draft(try await LocalWorkoutExtraction.onDevice(source)) }
    }
    private func loadPhoto() {
        guard let selected = photo else { return }
        photo = nil // Selecting the same image again is a valid retry.
        extract {
            guard let photo = try await selected.loadTransferable(type: BoundedWorkoutPhoto.self) else {
                throw WorkoutError.invalidInput(L10n.s("This photo could not be read. Try a file or paste the workout text."))
            }
            try Task.checkCancellation()
            return .text(try await LocalWorkoutExtraction.recognize(photo.data))
        }
    }
    private func recognize(_ data: Data) {
        extract { .text(try await LocalWorkoutExtraction.recognize(data)) }
    }

}

struct WorkoutEditorView: View {
    let store: PhoneStore
    let routineID: UUID?
    let finished: () -> Void
    @State private var draft: WorkoutDraft
    @State private var useToday: Bool
    @State private var editMode = EditMode.inactive
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    // The draft is an intentional editing snapshot; external sync cannot alter it.
    init(store: PhoneStore, initial: WorkoutDraft, routineID: UUID?, useToday: Bool = false, finished: @escaping () -> Void = {}) {
        self.store = store; self.routineID = routineID; self.finished = finished
        _draft = State(initialValue: initial); _useToday = State(initialValue: useToday)
    }
    private var validationMessage: String? {
        do { _ = try draft.validated(); return nil } catch { return error.localizedDescription }
    }
    var body: some View {
        LiftForm {
            if draft.exercises.contains(where: { !$0.fieldsToReview.isEmpty }) {
                Section { Label(L10n.s("\(draft.exercises.filter { !$0.fieldsToReview.isEmpty }.count) exercises need a decision"), systemImage: "pencil.circle").font(.callout)
                    Text(L10n.s("Open the marked exercises. Missing values stay empty until you confirm them.")).font(.caption).foregroundStyle(.secondary) }
            }
            Section(L10n.s("Workout name")) { TextField(L10n.s("Workout name"), text: $draft.title).font(LiftType.title).padding(.vertical, 6).accessibilityLabel(L10n.s("Workout name")) }
            Section {
                ForEach($draft.exercises) { $exercise in
                    NavigationLink {
                        DraftExerciseEditorView(exercise: $exercise) { draft.removeExercise(exercise.id) }
                    } label: { DraftExerciseSummary(exercise: exercise) }
                }
                .onMove { draft.exercises.move(fromOffsets: $0, toOffset: $1) }
                Button { draft.exercises.append(DraftExercise()) } label: { Label(L10n.s("Add exercise"), systemImage: "plus") }
                    .disabled(draft.exercises.count >= 50)
            } header: {
                HStack {
                    Text(L10n.s("Exercises · \(draft.exercises.count)"))
                    Spacer()
                    Button(editMode == .active ? L10n.s("Done") : L10n.s("Reorder")) { editMode = editMode == .active ? .inactive : .active }
                        .font(.caption).frame(minHeight: 44)
                        .disabled(draft.exercises.count < 2)
                }
            }
            if !draft.notes.isEmpty || !draft.source.isEmpty {
                Section { DisclosureGroup(L10n.s("Source & import notes")) {
                    ForEach(draft.notes, id: \.self) { Text($0).font(.caption) }
                    if !draft.source.isEmpty { Text(draft.source).font(.caption).textSelection(.enabled) }
                } }
            }
            if let plan = try? draft.validated() {
                Section { DisclosureGroup(L10n.s("Collection & approved alternatives")) {
                    ObservationCollectionView(plan: plan)
                    ForEach(plan.exercises.filter { !($0.alternatives ?? []).isEmpty }) { exercise in
                        Text(L10n.s("Alternatives for \(exercise.name)")).font(.callout)
                        ForEach(exercise.alternatives ?? []) { item in
                            Text(L10n.s("\(item.name): \(WorkoutSession.number(item.weight)) \(item.unit.rawValue) × \(item.reps), \(item.restSeconds)s rest · \(item.loadConvention.label)")).font(.caption)
                        }
                    }
                } }
            }
            Section(L10n.s("Between exercises")) {
                Stepper(L10n.s("Machine change · \(draft.original?.transitionSeconds ?? 0) sec"), value: Binding(get: { draft.original?.transitionSeconds ?? 0 }, set: { value in
                    if draft.original == nil { draft.original = WorkoutPlan(title: draft.title, exercises: []) }
                    draft.original?.transitionSeconds = value
                }), in: 0...300, step: 15)
                Text(L10n.s("Optional preparation time after prescribed rest. Ready skips it immediately.")).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker(L10n.s("Save to"), selection: $useToday) {
                    Text(L10n.s("Routine library")).tag(false)
                    Text(L10n.s("Today & library")).tag(true)
                }
                Text(useToday ? L10n.s("Save this reviewed workout and send it to Watch. A workout already in progress keeps its original plan.") : L10n.s("Save for later. Today and any active workout stay as they are."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let message = error ?? validationMessage { Section(L10n.s("Needs attention")) { Text(message).font(.footnote).foregroundStyle(.secondary) } }
        }
        .environment(\.editMode, $editMode)
        .scrollContentBackground(.hidden).background(.black)
        .navigationTitle(L10n.s("Edit workout")).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(useToday ? L10n.s("Save and send to Watch") : L10n.s("Save routine")) { save() }
                .buttonStyle(QuietButtonStyle(prominent: true)).disabled(validationMessage != nil)
                .padding(.horizontal, 20).padding(.vertical, 10).background(.black)
        }
        .onChange(of: draft) { error = nil }
    }
    private func save() {
        do {
            try store.saveWorkout(draft.validated(), replacing: routineID, useToday: useToday)
            finished(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct DraftExerciseEditorView: View {
    @Binding var exercise: DraftExercise
    let remove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemoval = false
    var body: some View {
        LiftForm {
            Section { DraftExerciseFields(exercise: $exercise) }
            Section { Button(L10n.s("Remove exercise")) { confirmingRemoval = true } }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle(L10n.s("Exercise")).navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(L10n.s("Remove this exercise?"), isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button(L10n.s("Remove exercise")) { dismiss(); remove() }
                Button(L10n.s("Cancel"), role: .cancel) { }
            } message: { Text(L10n.s("Its targets, alternatives and coach requests will be removed from this draft. Saved history is kept.")) }
    }
}

struct DraftExerciseSummary: View {
    let exercise: DraftExercise
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(exercise.name.isEmpty ? L10n.s("New exercise") : exercise.name).font(.body)
            Text(exercise.kind != nil && exercise.kind != .strength ? ((try? exercise.exercise())?.activity?.summary ?? L10n.s("Complete activity details")) : L10n.s("\(exercise.sets.isEmpty ? "?" : exercise.sets) × \(exercise.reps.isEmpty ? "?" : exercise.reps) · \(exercise.weight.isEmpty ? "?" : exercise.weight) \(exercise.unit) · \(exercise.rest.isEmpty ? "?" : exercise.rest)s rest"))
                .font(.caption).foregroundStyle(.secondary)
            if !exercise.fieldsToReview.isEmpty { Text(L10n.s("Review: \(exercise.fieldsToReview.joined(separator: " · "))")).font(.caption).foregroundStyle(.secondary) }
            if exercise.optionalWork { Text(L10n.s("Optional · priority \(exercise.priority)")).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }
}

struct DraftExerciseFields: View {
    @Binding var exercise: DraftExercise
    var body: some View {
        TextField(L10n.s("Exercise name"), text: $exercise.name).accessibilityLabel(L10n.s("Exercise name"))
        Picker(L10n.s("Activity type"), selection: $exercise.kind) {
            Text(L10n.s("Choose type")).tag(ActivityKind?.none)
            ForEach(ActivityKind.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
        }
        if exercise.kind == .strength || (exercise.kind == nil && !exercise.sets.isEmpty) {
        field(L10n.s("Sets"), value: $exercise.sets); field(L10n.s("Repetitions"), value: $exercise.reps)
        field(L10n.s("Load"), value: $exercise.weight)
        Picker(L10n.s("Unit"), selection: $exercise.unit) { Text(L10n.s("Choose")).tag(""); Text(L10n.s("kg")).tag("kg"); Text(L10n.s("lb")).tag("lb") }
        field(L10n.s("Rest · seconds"), value: $exercise.rest)
        } else if exercise.kind != nil {
            field(L10n.s("Duration · minutes"), value: $exercise.durationMinutes, required: false)
            Picker(L10n.s("Distance unit"), selection: $exercise.distanceUnit) { Text(L10n.s("km")).tag(DistanceUnit.km); Text(L10n.s("mi")).tag(DistanceUnit.mi) }
            field(L10n.s("Distance · optional"), value: $exercise.distance, required: false)
            field(exercise.distanceUnit == .km ? L10n.s("Speed · km/h") : L10n.s("Speed · mph"), value: $exercise.speed, required: false)
            field(L10n.s("Incline · %"), value: $exercise.incline, required: false)
            DisclosureGroup(L10n.s("Added load · only if prescribed")) {
                field(L10n.s("Added load"), value: $exercise.addedLoad, required: false)
                Picker(L10n.s("Unit"), selection: $exercise.unit) { Text(L10n.s("Choose")).tag(""); Text(L10n.s("kg")).tag("kg"); Text(L10n.s("lb")).tag("lb") }
            }
            Text(L10n.s("Targets only. Unknown values stay empty; actual results are logged separately.")).font(.caption).foregroundStyle(.secondary)
        }
        DisclosureGroup(L10n.s("Comparison & optional work")) {
            if exercise.kind == .strength || exercise.kind == nil {
            Picker(L10n.s("Load convention"), selection: $exercise.convention) {
                Text(L10n.s("Unspecified")).tag("")
                ForEach(LoadConvention.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
            }
            TextField(L10n.s("Variation key"), text: $exercise.comparisonID).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel(L10n.s("Variation key"))
            Text(L10n.s("Use the same key only for the same machine and variation. Convention and key go together; leave both blank if unknown.")).font(.caption).foregroundStyle(.secondary)
            }
            Toggle(L10n.s("Optional work"), isOn: $exercise.optionalWork)
            Picker(L10n.s("Priority"), selection: $exercise.priority) { ForEach(1...5, id: \.self) { Text(L10n.s("\($0)\($0 == 1 ? " · highest" : "")")).tag($0) } }
            Text(L10n.s("Only approved optional work can be skipped to fit your available time.")).font(.caption).foregroundStyle(.secondary)
        }
        if !exercise.source.isEmpty { DisclosureGroup(L10n.s("Source text")) { Text(exercise.source).font(.caption).foregroundStyle(.secondary) } }
        if exercise.kind == .strength { Text(L10n.s("Use 0 only for confirmed unweighted work or explicitly prescribed zero rest.")).font(.caption).foregroundStyle(.secondary) }
    }
    private func field(_ label: String, value: Binding<String>, required: Bool = true) -> some View {
        LabeledContent(label) { TextField(required ? L10n.s("Required") : L10n.s("Optional"), text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel(label) }
    }
}
struct RoutineLibraryView: View {
    let store: PhoneStore
    @State private var importing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LiftPageHeading(title: L10n.s("Your routines"), detail: L10n.s("Choose a workout. Make it today’s plan."))
                LiftSurface {
                    NavigationLink { ScheduleView(store: store) } label: {
                        LiftMenuRow(title: L10n.s("Weekly schedule"), symbol: "calendar", detail: scheduleDescription)
                    }
                }
                LiftSection(title: L10n.s("Saved workouts")) {
                    if store.state.routineLibrary.isEmpty {
                        Text(L10n.s("Save a workout to keep it here for next time.")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let plan = store.state.plan, !store.state.routineLibrary.contains(where: { $0.plan.id == plan.id }) {
                        Button(L10n.s("Save Today to library")) { do { try store.saveRoutine(plan) } catch { store.error = error.localizedDescription } }
                            .buttonStyle(QuietButtonStyle())
                    }
                    LazyVStack(spacing: 12) {
                        ForEach(store.state.routineLibrary) { routine in
                            NavigationLink { RoutineDetailView(store: store, routineID: routine.id) } label: {
                                LiftSurface {
                                    VStack(alignment: .leading, spacing: 16) {
                                        HStack(alignment: .top) {
                                            Text(routine.plan.title).font(LiftType.title)
                                            Spacer(minLength: 16)
                                            LiftChevron().padding(.top, 7)
                                        }
                                        HStack {
                                            Text(LiftCopy.workoutSummary(routine.plan)).font(.caption).foregroundStyle(.secondary)
                                            Spacer(minLength: 8)
                                            if store.state.plan == routine.plan {
                                                Label(L10n.s("Today"), systemImage: "checkmark").font(.caption)
                                            }
                                        }
                                    }.padding(20)
                                }
                            }
                        }
                    }
                }
            }.padding(24).modifier(LiftContentEntrance())
        }.buttonStyle(.plain).background(.black).modifier(LiftRootChrome())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button { importing = true } label: { Label(L10n.s("Add a routine"), systemImage: "plus").padding(.vertical, 3) }
                    .buttonStyle(QuietButtonStyle(prominent: true)).padding(.horizontal, 24).padding(.vertical, 12).background(.black)
            }
            .sheet(isPresented: $importing) { SmartImportView(store: store) }
    }
    private var scheduleDescription: String {
        let days = store.state.weeklySchedule.count
        return days == 0 ? L10n.s("Plan your training days") : (days == 1 ? L10n.s("1 day planned") : L10n.s("\(days) days planned"))
    }
}
struct RoutineDetailView: View {
    let store: PhoneStore
    let routineID: UUID
    var body: some View {
        ScrollView {
            if let routine = store.state.routineLibrary.first(where: { $0.id == routineID }) {
                VStack(alignment: .leading, spacing: 28) {
                    LiftPageHeading(title: routine.plan.title, detail: LiftCopy.workoutSummary(routine.plan))
                    LiftSurface {
                        ForEach(routine.plan.exercises) { exercise in
                            VStack(alignment: .leading, spacing: 0) {
                                LiftExerciseRow(exercise: exercise, unit: routine.plan.unit,
                                                number: (routine.plan.exercises.firstIndex(where: { $0.id == exercise.id }) ?? 0) + 1).padding(18)
                                NavigationLink { AlternativesEditorView(store: store, routine: routine, exerciseID: exercise.id) } label: {
                                    HStack { Text(L10n.s("Approved alternatives")); Spacer(); LiftChevron() }.font(.caption).foregroundStyle(.secondary)
                                        .padding(.horizontal, 18).frame(minHeight: 44)
                                }
                                if exercise.id != routine.plan.exercises.last?.id { Divider().padding(.horizontal, 18) }
                            }
                        }
                    }
                    DisclosureGroup(L10n.s("Coach observations")) { ObservationCollectionView(plan: routine.plan) }
                    if !routine.previousVersions.isEmpty {
                        DisclosureGroup(L10n.s("Previous prescriptions")) {
                            ForEach(routine.previousVersions) { Text(L10n.s("\($0.title) · \($0.totalSets) prescribed sets")).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }.padding(24)
            }
        }.buttonStyle(.plain).background(.black).navigationTitle(L10n.s("Routine")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let routine = store.state.routineLibrary.first(where: { $0.id == routineID }) {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(L10n.s("Edit")) { WorkoutEditorView(store: store, initial: WorkoutDraft(plan: routine.plan), routineID: routine.id) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let routine = store.state.routineLibrary.first(where: { $0.id == routineID }) {
                    Button(store.state.plan == routine.plan ? L10n.s("Selected for Today") : L10n.s("Use today & send to Watch")) {
                        do { try store.chooseRoutine(routine) } catch { store.error = error.localizedDescription }
                    }.buttonStyle(QuietButtonStyle(prominent: true)).disabled(store.state.plan == routine.plan)
                        .padding(.horizontal, 24).padding(.vertical, 12).background(.black)
                }
            }
    }
}
struct ScheduleView: View {
    let store: PhoneStore
    var body: some View {
        LiftForm { ForEach(1...7, id: \.self) { day in
            Picker(Calendar.current.weekdaySymbols[day - 1], selection: Binding<UUID?>(get: { store.state.weeklySchedule.first { $0.weekday == day }?.routineID }, set: { id in do { try store.scheduleRoutine(id, weekday: day) } catch { store.error = error.localizedDescription } })) {
                Text(L10n.s("No routine")).tag(nil as UUID?)
                ForEach(store.state.routineLibrary) { Text($0.plan.title).tag(Optional($0.id)) }
            }
        } }.scrollContentBackground(.hidden).background(.black).navigationTitle(L10n.s("Weekly schedule")).navigationBarTitleDisplayMode(.inline)
    }
}
struct HistoryImportView: View {
    let store: PhoneStore
    @State private var text = ""
    @State private var records: [HistoricalWorkout] = []
    @State private var confirmed = false
    @State private var error: String?
    @State private var saved = false
    var body: some View {
        LiftForm {
            Section(L10n.s("Confirmed historical records")) {
                Text(L10n.s("Import actual results from your notes or coach. These remain labelled imported; no Little Lift timing or observations are invented."))
                ShareLink(item: HistoryImport.example) { Text(L10n.s("Share history format")) }
                PasteButton(payloadType: String.self) { text = $0.joined(separator: "\n") }
                TextEditor(text: $text).frame(height: 200).font(.caption.monospaced()).accessibilityLabel(L10n.s("Historical workout JSON"))
                Button(L10n.s("Preview records")) { do { records = try HistoryImport.parse(text); error = nil } catch { self.error = error.localizedDescription } }
            }
            ForEach(records) { record in Section(record.title) { Text(record.report()).font(.caption).textSelection(.enabled) } }
            if !records.isEmpty {
                Toggle(L10n.s("These are actual completed results I have checked"), isOn: $confirmed)
                Button(saved ? L10n.s("Records saved") : L10n.s("Import confirmed records")) { do { try store.importHistory(records); saved = true } catch { self.error = error.localizedDescription } }.disabled(!confirmed || saved)
            }
            if let error { Text(error) }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle(L10n.s("Import history")).navigationBarTitleDisplayMode(.inline)
            .onChange(of: text) { records = []; confirmed = false; saved = false }
    }
}
struct AlternativesEditorView: View {
    let store: PhoneStore
    let routine: Routine
    let exerciseID: UUID
    @State private var alternative = DraftExercise()
    @State private var approved = false
    @State private var message: String?
    var body: some View {
        LiftForm {
            Section { Text(L10n.s("Only add alternatives you or your coach already approved. A different machine/variation needs a different exact variation ID. This approval applies to future workouts; active sessions keep their copied prescription.")) }
            Section(L10n.s("Alternative prescription")) { DraftExerciseFields(exercise: $alternative) }
            Toggle(L10n.s("I approve this alternative and its targets"), isOn: $approved)
            Button(L10n.s("Save approved alternative")) {
                do {
                    let item = try alternative.exercise()
                    guard let comparisonID = item.comparisonID, let convention = item.loadConvention, let unit = WeightUnit(rawValue: alternative.unit) else { throw WorkoutError.invalidInput(L10n.s("An alternative requires units, a load convention and exact variation ID.")) }
                    var plan = store.state.routineLibrary.first(where: { $0.id == routine.id })?.plan ?? routine.plan
                    guard let i = plan.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
                    guard comparisonID != plan.exercises[i].comparisonID else { throw WorkoutError.invalidInput(L10n.s("Use a different variation ID for a different machine or variation.")) }
                    var all = plan.exercises[i].alternatives ?? []
                    all.append(ExerciseAlternative(name: item.name, comparisonID: comparisonID, loadConvention: convention, unit: unit, reps: item.reps, weight: item.weight, restSeconds: item.restSeconds))
                    plan.exercises[i].alternatives = all; try store.saveRoutine(plan, replacing: routine.id)
                    message = L10n.s("Approved alternative saved for future sessions."); approved = false
                } catch { message = error.localizedDescription }
            }.disabled(!approved)
            if let message { Text(message) }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle(L10n.s("Approved alternative")).navigationBarTitleDisplayMode(.inline)
            .onAppear { alternative.sets = "1"; alternative.unit = routine.plan.unit.rawValue }
            .onChange(of: alternative) { approved = false }
    }
}

/// Choosing is preview-only until the user explicitly saves Today.
struct WorkoutChooserView: View {
    let store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var scheduledRoutine: Routine? {
        guard let slot = store.state.weeklySchedule.first(where: { $0.weekday == Calendar.current.component(.weekday, from: .now) }) else { return nil }
        return store.state.routineLibrary.first { $0.id == slot.routineID }
    }
    private var routines: [Routine] {
        store.state.routineLibrary.filter {
            search.isEmpty ? $0.id != scheduledRoutine?.id : $0.plan.title.localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        NavigationStack {
            LiftList {
                if let routine = scheduledRoutine, search.isEmpty {
                    Section(L10n.s("Scheduled today")) { choice(routine) }
                }
                if !routines.isEmpty || scheduledRoutine == nil || !search.isEmpty {
                    Section(scheduledRoutine != nil && search.isEmpty ? L10n.s("Other workouts") : L10n.s("Saved workouts")) {
                        ForEach(routines) { choice($0) }
                        if routines.isEmpty { Text(search.isEmpty ? L10n.s("Your library is empty. Import a workout to save it here.") : L10n.s("No matching workouts.")).foregroundStyle(.secondary) }
                    }
                }
            }
            .searchable(text: $search, prompt: L10n.s("Find a workout"))
            .scrollContentBackground(.hidden).background(.black)
            .navigationTitle(L10n.s("Choose workout")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.s("Close")) { dismiss() } } }
        }.tint(.white).presentationBackground(.black)
    }
    private func choice(_ routine: Routine) -> some View {
        NavigationLink {
            WorkoutChoicePreview(store: store, routineID: routine.id) { dismiss() }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(routine.plan.title)
                    if store.state.plan == routine.plan { Image(systemName: "checkmark").font(.caption).accessibilityLabel(L10n.s("Selected for Today")) }
                }
                Text(LiftCopy.workoutSummary(routine.plan)).font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        }
    }
}

struct WorkoutChoicePreview: View {
    let store: PhoneStore
    let routineID: UUID
    let finished: () -> Void
    @State private var error: String?
    var body: some View {
        if let routine = store.state.routineLibrary.first(where: { $0.id == routineID }) {
            LiftList {
                Section {
                    Text(routine.plan.title).font(.title3.weight(.regular))
                    Text(L10n.s("\(routine.plan.totalSets) sets · \(routine.plan.unit.rawValue)")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(routine.plan.exercises) { exercise in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(exercise.name)
                        Text(exercise.prescription(unit: routine.plan.unit)).font(.caption).foregroundStyle(.secondary)
                        if let convention = exercise.loadConvention { Text(convention.label).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }
                Section { ObservationCollectionView(plan: routine.plan) }
                if let deadline = routine.plan.timeBudget?.finishAt, deadline < .now {
                    Section { Text(L10n.s("This routine has an old finish time. After choosing it, update Available time before starting.")).font(.footnote).foregroundStyle(.secondary) }
                }
                Section { Text(L10n.s("Only changes Today after you choose it. A workout already in progress on Watch keeps its plan.")).font(.footnote).foregroundStyle(.secondary) }
                if let error { Text(error).font(.footnote) }
            }
            .scrollContentBackground(.hidden).background(.black)
            .navigationTitle(L10n.s("Preview workout")).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(L10n.s("Use today and send to Watch")) {
                    do { try store.chooseRoutine(routine); finished() } catch { self.error = error.localizedDescription }
                }.buttonStyle(QuietButtonStyle()).padding(.horizontal, 20).padding(.vertical, 10).background(.black)
            }
        }
    }
}

/// Photos supplies a temporary local file; read it within the transfer callback
/// with the same actual-byte limit as Files, before handing data to ImageIO.
private struct BoundedWorkoutPhoto: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            BoundedWorkoutPhoto(data: try InputBoundary.read(received.file, maximumBytes: 20_000_000))
        }
    }
}
