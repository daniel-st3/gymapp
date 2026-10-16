import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct SmartImportView: View {
    let store: PhoneStore
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
                    LiftPageHeading(title: "Bring your workout", detail: "Paste text, read a screenshot or start from scratch. Review everything before saving.")
                    LiftSection(title: "Paste a workout") {
                        LiftSurface {
                            ZStack(alignment: .topLeading) {
                                if text.isEmpty {
                                    Text("Bench press · 3 × 8 · 40 kg\nRest 90 seconds")
                                        .font(.callout).foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.top, 8)
                                        .accessibilityHidden(true)
                                }
                                TextEditor(text: $text).font(.callout).frame(minHeight: 130).scrollContentBackground(.hidden)
                                    .scrollDismissesKeyboard(.interactively).accessibilityLabel("Workout source text")
                            }.padding(14)
                            Divider().padding(.horizontal, 18)
                            HStack {
                                PasteButton(payloadType: String.self) { text = $0.joined(separator: "\n") }
                                    .labelStyle(.titleOnly).buttonBorderShape(.capsule)
                                Spacer()
                                Text("Text or JSON").font(.caption).foregroundStyle(.secondary)
                            }.padding(14)
                        }
                    }
                    LiftSection(title: "Or choose a source") {
                        LiftSurface {
                            PhotosPicker(selection: $photo, matching: .images) {
                                LiftMenuRow(title: "Read a screenshot", symbol: "photo", detail: "Text recognition on this device")
                            }
                            Divider().padding(.horizontal, 18)
                            Button { importingFile = true } label: { LiftMenuRow(title: "Choose a file", symbol: "doc") }
                            Divider().padding(.horizontal, 18)
                            Button { draft = WorkoutDraft(); draft?.exercises = [DraftExercise()]; reviewing = true } label: {
                                LiftMenuRow(title: "Build a workout", symbol: "square.and.pencil")
                            }
                        }
                    }
                    DisclosureGroup("More import options") {
                        Button("Try Apple Intelligence") { modelExtract() }.buttonStyle(QuietButtonStyle())
                            .disabled(text.isEmpty || busy || !LocalWorkoutExtraction.modelAvailable)
                        Text(LocalWorkoutExtraction.availability).font(.caption).foregroundStyle(.secondary)
                        ShareLink(item: PlanImport.coachingPrompt) { Label("Share coaching prompt", systemImage: "square.and.arrow.up") }
                            .font(.subheadline).frame(minHeight: 44)
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.secondary).accessibilityLabel("Import needs attention. " + error) }
                }.disabled(busy).padding(24)
                if busy {
                    HStack { ProgressView("Reading workout…"); Spacer(); Button("Cancel") { cancelExtraction() }.frame(minHeight: 44) }
                        .padding(.horizontal, 24).padding(.bottom, 20)
                }
            }.buttonStyle(.plain).background(.black)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Button { parse() } label: { Label("Preview workout", systemImage: "list.bullet.rectangle") }.buttonStyle(QuietButtonStyle(prominent: true)).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                        .padding(.horizontal, 20).padding(.vertical, 10).background(.black)
                }
                .navigationDestination(isPresented: $reviewing) {
                    if let draft { WorkoutEditorView(store: store, initial: draft, routineID: nil, useToday: true) { dismiss() } }
                }
                .navigationTitle("Import workout").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .onChange(of: text) { draft = nil; error = nil }
                .onChange(of: photo) { loadPhoto() }
                .onDisappear { cancelExtraction() }
                .fileImporter(isPresented: $importingFile, allowedContentTypes: [.json, .plainText, .image]) { result in
                    do {
                        let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 20_000_000 else { throw WorkoutError.invalidInput("Choose a file below 20 MB.") }
                        let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
                        let data = try InputBoundary.read(url, maximumBytes: isImage ? 20_000_000 : 64_000)
                        if isImage { recognize(data) }
                        else { guard data.count <= 64_000, let value = String(data: data, encoding: .utf8) else { throw WorkoutError.invalidInput("Text imports must be UTF-8 and below 64 KB.") }; text = value }
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
            error = "Reading took too long. Try again, paste workout text, or build it manually."
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
                throw WorkoutError.invalidInput("This photo could not be read. Try a file or paste the workout text.")
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
            Section("Workout name") { TextField("Workout name", text: $draft.title).font(LiftType.title).padding(.vertical, 6).accessibilityLabel("Workout name") }
            Section {
                ForEach($draft.exercises) { $exercise in
                    NavigationLink {
                        DraftExerciseEditorView(exercise: $exercise) { draft.removeExercise(exercise.id) }
                    } label: { DraftExerciseSummary(exercise: exercise) }
                }
                .onMove { draft.exercises.move(fromOffsets: $0, toOffset: $1) }
                Button { draft.exercises.append(DraftExercise()) } label: { Label("Add exercise", systemImage: "plus") }
                    .disabled(draft.exercises.count >= 50)
            } header: {
                HStack {
                    Text("Exercises · \(draft.exercises.count)")
                    Spacer()
                    Button(editMode == .active ? "Done" : "Reorder") { editMode = editMode == .active ? .inactive : .active }
                        .font(.caption).frame(minHeight: 44)
                        .disabled(draft.exercises.count < 2)
                }
            }
            if !draft.notes.isEmpty || !draft.source.isEmpty {
                Section { DisclosureGroup("Source & import notes") {
                    ForEach(draft.notes, id: \.self) { Text($0).font(.caption) }
                    if !draft.source.isEmpty { Text(draft.source).font(.caption).textSelection(.enabled) }
                } }
            }
            if let plan = try? draft.validated() {
                Section { DisclosureGroup("Collection & approved alternatives") {
                    ObservationCollectionView(plan: plan)
                    ForEach(plan.exercises.filter { !($0.alternatives ?? []).isEmpty }) { exercise in
                        Text("Alternatives for \(exercise.name)").font(.callout)
                        ForEach(exercise.alternatives ?? []) { item in
                            Text("\(item.name): \(WorkoutSession.number(item.weight)) \(item.unit.rawValue) × \(item.reps), \(item.restSeconds)s rest · \(item.loadConvention.label)").font(.caption)
                        }
                    }
                } }
            }
            Section {
                Picker("Save to", selection: $useToday) {
                    Text("Routine library").tag(false)
                    Text("Today & library").tag(true)
                }
                Text(useToday ? "Save this reviewed workout and send it to Watch. A workout already in progress keeps its original plan." : "Save for later. Today and any active workout stay as they are.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let message = error ?? validationMessage { Section("Needs attention") { Text(message).font(.footnote).foregroundStyle(.secondary) } }
        }
        .environment(\.editMode, $editMode)
        .scrollContentBackground(.hidden).background(.black)
        .navigationTitle("Edit workout").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(useToday ? "Save and send to Watch" : "Save routine") { save() }
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
            Section { Button("Remove exercise") { confirmingRemoval = true } }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle("Exercise").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Remove this exercise?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("Remove exercise") { dismiss(); remove() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Its targets, alternatives and coach requests will be removed from this draft. Saved history is kept.") }
    }
}

struct DraftExerciseSummary: View {
    let exercise: DraftExercise
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(exercise.name.isEmpty ? "New exercise" : exercise.name).font(.body)
            Text("\(exercise.sets.isEmpty ? "?" : exercise.sets) × \(exercise.reps.isEmpty ? "?" : exercise.reps) · \(exercise.weight.isEmpty ? "?" : exercise.weight) \(exercise.unit) · \(exercise.rest.isEmpty ? "?" : exercise.rest)s rest")
                .font(.caption).foregroundStyle(.secondary)
            if (try? exercise.exercise()) == nil { Text("Complete missing details").font(.caption).foregroundStyle(.secondary) }
            if exercise.optionalWork { Text("Optional · priority \(exercise.priority)").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }
}

struct DraftExerciseFields: View {
    @Binding var exercise: DraftExercise
    var body: some View {
        TextField("Exercise name", text: $exercise.name).accessibilityLabel("Exercise name")
        field("Sets", value: $exercise.sets); field("Repetitions", value: $exercise.reps)
        field("Load", value: $exercise.weight)
        Picker("Unit", selection: $exercise.unit) { Text("Choose").tag(""); Text("kg").tag("kg"); Text("lb").tag("lb") }
        field("Rest · seconds", value: $exercise.rest)
        DisclosureGroup("Comparison & optional work") {
            Picker("Load convention", selection: $exercise.convention) {
                Text("Unspecified").tag("")
                ForEach(LoadConvention.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
            }
            TextField("Variation key", text: $exercise.comparisonID).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Variation key")
            Text("Use the same key only for the same machine and variation. Convention and key go together; leave both blank if unknown.").font(.caption).foregroundStyle(.secondary)
            Toggle("Optional work", isOn: $exercise.optionalWork)
            Picker("Priority", selection: $exercise.priority) { ForEach(1...5, id: \.self) { Text("\($0)\($0 == 1 ? " · highest" : "")").tag($0) } }
            Text("Only approved optional work can be skipped to fit your available time.").font(.caption).foregroundStyle(.secondary)
        }
        if !exercise.source.isEmpty { DisclosureGroup("Source text") { Text(exercise.source).font(.caption).foregroundStyle(.secondary) } }
        Text("Use 0 only for confirmed unweighted work or explicitly prescribed zero rest.").font(.caption).foregroundStyle(.secondary)
    }
    private func field(_ label: String, value: Binding<String>) -> some View {
        LabeledContent(label) { TextField("Required", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel(label) }
    }
}
struct RoutineLibraryView: View {
    let store: PhoneStore
    @State private var importing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LiftPageHeading(title: "Your routines", detail: "Choose a workout. Make it today’s plan.")
                LiftSurface {
                    NavigationLink { ScheduleView(store: store) } label: {
                        LiftMenuRow(title: "Weekly schedule", symbol: "calendar", detail: scheduleDescription)
                    }
                }
                LiftSection(title: "Saved workouts") {
                    if store.state.routineLibrary.isEmpty {
                        Text("Save a workout to keep it here for next time.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let plan = store.state.plan, !store.state.routineLibrary.contains(where: { $0.plan.id == plan.id }) {
                        Button("Save Today to library") { do { try store.saveRoutine(plan) } catch { store.error = error.localizedDescription } }
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
                                                Label("Today", systemImage: "checkmark").font(.caption)
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
                Button { importing = true } label: { Label("Add a routine", systemImage: "plus").padding(.vertical, 3) }
                    .buttonStyle(QuietButtonStyle(prominent: true)).padding(.horizontal, 24).padding(.vertical, 12).background(.black)
            }
            .sheet(isPresented: $importing) { SmartImportView(store: store) }
    }
    private var scheduleDescription: String {
        let days = store.state.weeklySchedule.count
        return days == 0 ? "Plan your training days" : "\(days) \(days == 1 ? "day" : "days") planned"
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
                                    HStack { Text("Approved alternatives"); Spacer(); LiftChevron() }.font(.caption).foregroundStyle(.secondary)
                                        .padding(.horizontal, 18).frame(minHeight: 44)
                                }
                                if exercise.id != routine.plan.exercises.last?.id { Divider().padding(.horizontal, 18) }
                            }
                        }
                    }
                    DisclosureGroup("Coach observations") { ObservationCollectionView(plan: routine.plan) }
                    if !routine.previousVersions.isEmpty {
                        DisclosureGroup("Previous prescriptions") {
                            ForEach(routine.previousVersions) { Text("\($0.title) · \($0.totalSets) prescribed sets").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }.padding(24)
            }
        }.buttonStyle(.plain).background(.black).navigationTitle("Routine").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let routine = store.state.routineLibrary.first(where: { $0.id == routineID }) {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink("Edit") { WorkoutEditorView(store: store, initial: WorkoutDraft(plan: routine.plan), routineID: routine.id) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let routine = store.state.routineLibrary.first(where: { $0.id == routineID }) {
                    Button(store.state.plan == routine.plan ? "Selected for Today" : "Use today & send to Watch") {
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
                Text("No routine").tag(nil as UUID?)
                ForEach(store.state.routineLibrary) { Text($0.plan.title).tag(Optional($0.id)) }
            }
        } }.scrollContentBackground(.hidden).background(.black).navigationTitle("Weekly schedule").navigationBarTitleDisplayMode(.inline)
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
            Section("Confirmed historical records") {
                Text("Import actual results from your notes or coach. These remain labelled imported; no Little Lift timing or observations are invented.")
                ShareLink(item: HistoryImport.example) { Text("Share history format") }
                PasteButton(payloadType: String.self) { text = $0.joined(separator: "\n") }
                TextEditor(text: $text).frame(height: 200).font(.caption.monospaced()).accessibilityLabel("Historical workout JSON")
                Button("Preview records") { do { records = try HistoryImport.parse(text); error = nil } catch { self.error = error.localizedDescription } }
            }
            ForEach(records) { record in Section(record.title) { Text(record.report()).font(.caption).textSelection(.enabled) } }
            if !records.isEmpty {
                Toggle("These are actual completed results I have checked", isOn: $confirmed)
                Button(saved ? "Records saved" : "Import confirmed records") { do { try store.importHistory(records); saved = true } catch { self.error = error.localizedDescription } }.disabled(!confirmed || saved)
            }
            if let error { Text(error) }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle("Import history").navigationBarTitleDisplayMode(.inline)
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
            Section { Text("Only add alternatives you or your coach already approved. A different machine/variation needs a different exact variation ID. This approval applies to future workouts; active sessions keep their copied prescription.") }
            Section("Alternative prescription") { DraftExerciseFields(exercise: $alternative) }
            Toggle("I approve this alternative and its targets", isOn: $approved)
            Button("Save approved alternative") {
                do {
                    let item = try alternative.exercise()
                    guard let comparisonID = item.comparisonID, let convention = item.loadConvention, let unit = WeightUnit(rawValue: alternative.unit) else { throw WorkoutError.invalidInput("An alternative requires units, a load convention and exact variation ID.") }
                    var plan = store.state.routineLibrary.first(where: { $0.id == routine.id })?.plan ?? routine.plan
                    guard let i = plan.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
                    guard comparisonID != plan.exercises[i].comparisonID else { throw WorkoutError.invalidInput("Use a different variation ID for a different machine or variation.") }
                    var all = plan.exercises[i].alternatives ?? []
                    all.append(ExerciseAlternative(name: item.name, comparisonID: comparisonID, loadConvention: convention, unit: unit, reps: item.reps, weight: item.weight, restSeconds: item.restSeconds))
                    plan.exercises[i].alternatives = all; try store.saveRoutine(plan, replacing: routine.id)
                    message = "Approved alternative saved for future sessions."; approved = false
                } catch { message = error.localizedDescription }
            }.disabled(!approved)
            if let message { Text(message) }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle("Approved alternative").navigationBarTitleDisplayMode(.inline)
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
                    Section("Scheduled today") { choice(routine) }
                }
                if !routines.isEmpty || scheduledRoutine == nil || !search.isEmpty {
                    Section(scheduledRoutine != nil && search.isEmpty ? "Other workouts" : "Saved workouts") {
                        ForEach(routines) { choice($0) }
                        if routines.isEmpty { Text(search.isEmpty ? "Your library is empty. Import a workout to save it here." : "No matching workouts.").foregroundStyle(.secondary) }
                    }
                }
            }
            .searchable(text: $search, prompt: "Find a workout")
            .scrollContentBackground(.hidden).background(.black)
            .navigationTitle("Choose workout").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.tint(.white).presentationBackground(.black)
    }
    private func choice(_ routine: Routine) -> some View {
        NavigationLink {
            WorkoutChoicePreview(store: store, routineID: routine.id) { dismiss() }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(routine.plan.title)
                    if store.state.plan == routine.plan { Image(systemName: "checkmark").font(.caption).accessibilityLabel("Selected for Today") }
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
                    Text("\(routine.plan.totalSets) sets · \(routine.plan.unit.rawValue)").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(routine.plan.exercises) { exercise in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(exercise.name)
                        Text("\(exercise.sets) × \(exercise.reps) · \(WorkoutSession.number(exercise.weight)) \(routine.plan.unit.rawValue) · \(exercise.restSeconds)s rest").font(.caption).foregroundStyle(.secondary)
                        if let convention = exercise.loadConvention { Text(convention.label).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }
                Section { ObservationCollectionView(plan: routine.plan) }
                if let deadline = routine.plan.timeBudget?.finishAt, deadline < .now {
                    Section { Text("This routine has an old finish time. After choosing it, update Available time before starting.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section { Text("Only changes Today after you choose it. A workout already in progress on Watch keeps its plan.").font(.footnote).foregroundStyle(.secondary) }
                if let error { Text(error).font(.footnote) }
            }
            .scrollContentBackground(.hidden).background(.black)
            .navigationTitle("Preview workout").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("Use today and send to Watch") {
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
