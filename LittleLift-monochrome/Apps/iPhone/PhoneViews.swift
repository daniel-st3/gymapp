import SwiftUI
import UniformTypeIdentifiers

struct PhoneRootView: View {
    @Bindable var store: PhoneStore
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView {
            Tab("Today", systemImage: "dumbbell") { NavigationStack { TodayView(store: store) } }
            Tab("History", systemImage: "list.bullet.rectangle") { NavigationStack { HistoryView(store: store) } }
            Tab("Progress", systemImage: "chart.bar.xaxis") { NavigationStack { TrainingProgressView(store: store) } }
            Tab("Routines", systemImage: "square.stack") { NavigationStack { RoutineLibraryView(store: store) } }
            Tab("Settings", systemImage: "slider.horizontal.3") { NavigationStack { SettingsView(store: store) } }
        }
        .sheet(isPresented: $store.showingReviewQueue) { NavigationStack { ReviewQueueView(store: store).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { store.showingReviewQueue = false } } } } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.sendToWatch() } }
        .alert("Couldn’t save", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct TodayView: View {
    let store: PhoneStore
    @State private var importing = false
    @State private var choosing = false
    @State private var editing: WorkoutPlan?
    @State private var reviewing = false
    @State private var copies = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let plan = store.state.plan {
                    workoutHeader(plan)
                    LiftSection(title: "Your exercises") {
                        LiftSurface {
                            ForEach(plan.exercises) { exercise in
                                VStack(alignment: .leading, spacing: 0) {
                                    LiftExerciseRow(exercise: exercise, unit: plan.unit,
                                                    number: (plan.exercises.firstIndex(where: { $0.id == exercise.id }) ?? 0) + 1)
                                        .padding(18)
                                    if let previous = Progression.lastResult(for: exercise, unit: plan.unit, sessions: store.state.sessions) {
                                        NavigationLink { SessionDetailView(session: previous.session) } label: {
                                            HStack(spacing: 8) {
                                                Text("Last: \(WorkoutSession.number(previous.entry.weight)) \(plan.unit.rawValue) × \(previous.entry.reps)")
                                                Spacer(minLength: 8)
                                                Text("View set"); LiftChevron()
                                            }.font(.caption).foregroundStyle(.secondary)
                                                .padding(.horizontal, 18).frame(minHeight: 44)
                                        }.accessibilityLabel("Last matching final set, \(WorkoutSession.number(previous.entry.weight)) \(plan.unit.rawValue), \(previous.entry.reps) repetitions. View workout record.")
                                    }
                                    if exercise.id != plan.exercises.last?.id { Divider().padding(.horizontal, 18) }
                                }
                            }
                        }
                    }
                    LiftSurface {
                        NavigationLink { TimePlanningView(store: store) } label: {
                            LiftMenuRow(title: "Fit your available time", symbol: "clock")
                        }
                        Divider().padding(.horizontal, 18)
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 20) {
                                connectionActions
                                ObservationCollectionView(plan: plan)
                            }.padding(.horizontal, 18).padding(.bottom, 12)
                        } label: {
                            LiftMenuRow(title: "Coach & sharing", symbol: "bubble.left.and.text.bubble.right", disclosure: false)
                        }.padding(.trailing, 18)
                    }
                } else {
                    LiftPageHeading(title: "Your next workout", detail: "Bring a workout from your coach, a screenshot or your own notes.")
                    LiftSurface {
                        Button { importing = true } label: { LiftMenuRow(title: "Import a workout", symbol: "square.and.arrow.down", detail: "Review and edit before saving") }
                        if !store.state.routineLibrary.isEmpty {
                            Divider().padding(.horizontal, 18)
                            Button { choosing = true } label: { LiftMenuRow(title: "Choose a saved routine", symbol: "square.stack") }
                        }
                    }
                    Button("Try a generic example") {
                        do { try store.importPlan(PlanImport.example) } catch { store.error = error.localizedDescription }
                    }.font(.subheadline).frame(minHeight: 44)
                    connectionActions
                }
                if store.state.review != nil {
                    Button { reviewing = true } label: {
                        LiftSurface { LiftMenuRow(title: "A new workout to review", symbol: "text.bubble", detail: "Changes need your acceptance") }
                    }
                }
                NavigationLink { ReviewQueueView(store: store) } label: {
                    HStack { Text("Coach reviews").font(.subheadline); Spacer(); LiftChevron() }.frame(minHeight: 44)
                }
            }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 20)
                .modifier(LiftContentEntrance())
        }
        .buttonStyle(.plain)
        .background(.black)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { sendButton; importButton.fixedSize(horizontal: true, vertical: false) }
                VStack(spacing: 8) { sendButton; importButton }
            }.padding(.horizontal, 24).padding(.vertical, 12).background(.black)
        }
        .modifier(LiftRootChrome())
        .sheet(isPresented: $choosing) { WorkoutChooserView(store: store) }
        .sheet(item: $editing) { plan in
            NavigationStack {
                WorkoutEditorView(store: store, initial: WorkoutDraft(plan: plan), routineID: store.state.routineLibrary.first(where: { $0.plan == plan })?.id, useToday: true) { editing = nil }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil } } }
            }.tint(.white).presentationBackground(.black)
        }
        .sheet(isPresented: $importing) { SmartImportView(store: store) }
        .sheet(isPresented: $reviewing) { ReviewView(store: store) }
        .sensoryFeedback(.success, trigger: copies)
    }

    private var sendButton: some View {
        Button { store.sendToWatch() } label: {
            Label(store.isSyncing ? "Sending…" : "Send to Watch", systemImage: "applewatch")
                .padding(.horizontal, 10).padding(.vertical, 3)
        }.buttonStyle(QuietButtonStyle(prominent: true))
            .disabled(store.isSyncing || store.state.plan == nil)
    }

    private var importButton: some View {
        Button { importing = true } label: { Label("Import", systemImage: "plus").padding(.horizontal, 10).padding(.vertical, 3) }
            .buttonStyle(QuietButtonStyle()).accessibilityLabel("Import workout")
    }

    private func workoutHeader(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            LiftEyebrow(text: Date.now.formatted(.dateTime.weekday(.wide).month().day()))
            LiftPageHeading(title: plan.title)
            HStack(spacing: 16) {
                LiftStat(value: String(plan.exercises.count), label: "Exercises")
                LiftStat(value: String(plan.totalSets), label: "Sets")
                LiftStat(value: plan.unit.rawValue, label: "Load unit")
            }
            HStack(spacing: 10) {
                Button { choosing = true } label: { Label("Change workout", systemImage: "arrow.left.arrow.right") }
                    .buttonStyle(QuietButtonStyle())
                Button { editing = plan } label: { Label("Edit", systemImage: "pencil").padding(.horizontal, 12) }
                    .buttonStyle(QuietButtonStyle()).fixedSize(horizontal: true, vertical: false)
            }
            Label(store.syncMessage, systemImage: store.isSyncing ? "arrow.triangle.2.circlepath" : "applewatch")
                .font(.caption).foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .nonRepeating, value: reduceMotion ? false : store.isSyncing)
            if let slot = store.state.weeklySchedule.first(where: { $0.weekday == Calendar.current.component(.weekday, from: Date()) }),
               let routine = store.state.routineLibrary.first(where: { $0.id == slot.routineID }), routine.plan.id != plan.id {
                Button { choosing = true } label: {
                    Label("Scheduled: \(routine.plan.title)", systemImage: "calendar").font(.caption).frame(minHeight: 44)
                }
            }
        }
    }

    @ViewBuilder private var connectionActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.state.mode.title).font(.callout.weight(.medium))
            if store.state.mode == .existingChat {
                Button {
                    UIPasteboard.general.string = PlanImport.coachingPrompt; copies += 1
                } label: { Label(copies > 0 ? "Prompt copied" : "Copy coaching prompt", systemImage: copies > 0 ? "checkmark" : "doc.on.doc") }.buttonStyle(QuietButtonStyle())
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : LiftMotion.feedback, value: copies > 0)
            } else {
                Button("Run review Shortcut") {
                    var parts = URLComponents(); parts.scheme = "shortcuts"; parts.host = "run-shortcut"
                    parts.queryItems = [URLQueryItem(name: "name", value: "Little Lift Review")]
                    if let url = parts.url { openURL(url) }
                }.buttonStyle(QuietButtonStyle())
                NavigationLink("Set up the Shortcut") { ShortcutHelpView() }.font(.subheadline)
            }
        }.padding(.top, 8)
    }
}

struct ImportPlanView: View {
    let store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @State private var importingFile = false
    @State private var preview: WorkoutPlan?
    var body: some View {
        NavigationStack {
            LiftForm {
                Section {
                    Text("Copy the coaching prompt into your gym chat, then paste its JSON reply here. You’ll review the exercises before saving.")
                    ShareLink(item: PlanImport.coachingPrompt) { Label("Share coaching prompt", systemImage: "square.and.arrow.up") }
                }
                Section("Workout JSON") {
                    PasteButton(payloadType: String.self) { strings in text = strings.joined(separator: "\n"); preview = nil }
                    TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(height: 220)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .accessibilityLabel("Workout JSON")
                    Button("Choose a JSON or text file") { importingFile = true }
                    Button("Preview workout") {
                        do { preview = try PlanImport.parse(text); error = nil }
                        catch { self.error = error.localizedDescription }
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error { Section { Text(error).foregroundStyle(LiftStyle.error) } }
                if let preview {
                    Section(preview.title) {
                        ForEach(preview.exercises) { exercise in
                            VStack(alignment: .leading) {
                                Text(exercise.name)
                                Text("\(exercise.sets) × \(exercise.reps) · \(WorkoutSession.number(exercise.weight)) \(preview.unit.rawValue)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ObservationCollectionView(plan: preview)
                        Button("Save and send to watch") {
                            do { try store.acceptImportedPlan(preview); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(.black)
            .onChange(of: text) { preview = nil }
            .navigationTitle("Import workout").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.json, .plainText]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= 64_000 else { throw WorkoutError.invalidInput("Choose a file smaller than 64 KB.") }
                    let data = try InputBoundary.read(url, maximumBytes: 64_000)
                    guard let value = String(data: data, encoding: .utf8) else { throw WorkoutError.invalidInput("Choose a UTF-8 text file.") }
                    text = value
                } catch { self.error = error.localizedDescription }
            }
        }.tint(LiftStyle.accent).presentationBackground(.black)
    }
}

struct HistoryView: View {
    let store: PhoneStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LiftPageHeading(title: "Your training", detail: "Every set, kept in one place.")
                if !store.state.sessions.isEmpty {
                    HStack {
                        LiftStat(value: String(store.state.sessions.count), label: "Recorded workouts")
                        LiftStat(value: String(store.state.sessions.reduce(0) { $0 + $1.entries.count }), label: "Logged sets")
                    }
                    LiftSection(title: "Recorded with Little Lift") {
                        LazyVStack(spacing: 12) {
                            ForEach(store.state.sessions) { session in
                                NavigationLink { SessionDetailView(session: session) } label: {
                                    LiftSurface {
                                        HStack(alignment: .top, spacing: 20) {
                                            VStack(spacing: 4) {
                                                Text(session.startedAt, format: .dateTime.day()).font(.system(.title2, design: .serif))
                                                Text(session.startedAt, format: .dateTime.month(.abbreviated)).font(.caption).foregroundStyle(.secondary)
                                            }.frame(minWidth: 36)
                                            VStack(alignment: .leading, spacing: 9) {
                                                Text(session.plan.title).font(LiftType.heading)
                                                Text("\(session.entries.count) sets · \(Int(session.duration / 60)) min").font(.caption).foregroundStyle(.secondary)
                                                Text(session.startedAt, format: .dateTime.year().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                                            }.frame(maxWidth: .infinity, alignment: .leading)
                                            LiftChevron().padding(.top, 5)
                                        }.padding(20)
                                    }
                                }
                            }
                        }
                    }
                }
                if !store.state.externalHistory.isEmpty {
                    LiftSection(title: "Imported · user-confirmed") {
                        LiftSurface {
                            ForEach(store.state.externalHistory) { record in
                                NavigationLink {
                                    ScrollView { Text(record.report()).textSelection(.enabled).padding(24) }.background(.black).navigationTitle("Imported record")
                                } label: { LiftMenuRow(title: record.title, symbol: "doc.text", detail: String(record.date.prefix(10))) }
                                if record.id != store.state.externalHistory.last?.id { Divider().padding(.horizontal, 18) }
                            }
                        }
                    }
                }
                if store.state.sessions.isEmpty && store.state.externalHistory.isEmpty {
                    LiftSurface { VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "list.bullet.rectangle").font(.title2.weight(.light))
                        Text("Ready for your first workout").font(LiftType.title)
                        Text("Finish a workout on Watch. Your logged sets will appear here when your devices connect.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(24) }
                }
                NavigationLink { HistoryImportView(store: store) } label: {
                    LiftSurface { LiftMenuRow(title: "Import previous workouts", symbol: "square.and.arrow.down", detail: "Kept separate from app recordings") }
                }
            }.padding(24).modifier(LiftContentEntrance())
        }.buttonStyle(.plain).background(.black).modifier(LiftRootChrome())
    }
}

struct SessionDetailView: View {
    let session: WorkoutSession
    @State private var copies = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    LiftEyebrow(text: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    LiftPageHeading(title: session.plan.title)
                    HStack {
                        LiftStat(value: "\(session.entries.count) / \(session.plan.totalSets)", label: "Sets logged")
                        LiftStat(value: "\(Int(session.duration / 60)) min", label: "Session duration")
                    }
                }
                LiftSection(title: "Logged sets") {
                    ForEach(session.executionExercises) { exercise in
                        LiftSurface {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(exercise.name).font(.body)
                                Text("Target · \(exercise.sets) × \(exercise.reps) · \(WorkoutSession.number(exercise.weight)) \(session.plan.unit.rawValue)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Divider()
                                let entries = session.entries.filter { $0.exerciseID == exercise.id }
                                if entries.isEmpty { Text("Not completed").font(.subheadline).foregroundStyle(.secondary) }
                                ForEach(entries) { entry in
                                    MetricRow(title: "Set \(entry.setNumber)", value: "\(WorkoutSession.number(entry.weight)) \(session.plan.unit.rawValue) × \(entry.reps)")
                                }
                            }.padding(18)
                        }
                    }
                }
                if !session.plan.observationRequests.isEmpty {
                    LiftSection(title: "Coach observations") {
                        LiftSurface {
                            ForEach(session.observationEvidence) { evidence in
                                NavigationLink { ObservationDetailView(session: session, evidence: evidence) } label: {
                                    LiftMenuRow(title: evidence.title, symbol: "text.bubble", detail: evidence.detail)
                                }
                            }
                        }
                    }
                }
                if let changes = session.adjustments, !changes.isEmpty {
                    DisclosureGroup("Changes & original prescription") {
                        ForEach(changes) { Text($0.detail).font(.caption) }
                        ForEach(session.plan.exercises) { Text("Original: \($0.name) · \($0.sets) × \($0.reps) · \(WorkoutSession.number($0.weight)) \(session.plan.unit.rawValue)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                LiftSurface {
                    ShareLink(item: session.report()) { LiftMenuRow(title: "Share workout report", symbol: "square.and.arrow.up", disclosure: false) }
                    Divider().padding(.horizontal, 18)
                    Button { UIPasteboard.general.string = session.report(); copies += 1 } label: {
                        LiftMenuRow(title: copies > 0 ? "Report copied" : "Copy for my gym chat", symbol: copies > 0 ? "checkmark" : "doc.on.doc", disclosure: false)
                    }
                }
            }.padding(24).modifier(LiftContentEntrance())
        }.buttonStyle(.plain).background(.black).navigationTitle("Workout record").navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.success, trigger: copies)
    }
}

struct ObservationCollectionView: View {
    let plan: WorkoutPlan
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What will be collected").font(.callout.weight(.medium))
            if plan.observationRequests.isEmpty {
                Text("Your logged loads and repetitions. No additional coach observations requested.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(plan.observationRequests) { request in
                    Text(request.collectionDescription(in: plan)).font(.subheadline).foregroundStyle(.secondary)
                }
                Text("Stored on your devices. Included when you share a report or run your review Shortcut.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
    }
}

struct ObservationDetailView: View {
    let session: WorkoutSession
    let evidence: ObservationEvidence
    var body: some View {
        LiftList {
            Section(evidence.title) { Text(evidence.detail).textSelection(.enabled) }
            if let exercise = session.plan.exercises.first(where: { $0.id == evidence.exerciseID }) {
                Section("Set context") {
                    Text("Prescribed: \(WorkoutSession.number(exercise.weight)) \(session.plan.unit.rawValue) × \(exercise.reps) reps")
                    Text("Load convention: \(exercise.loadConvention?.label ?? "unspecified")")
                    if let entry = session.entries.first(where: { $0.id == evidence.setID }) {
                        Text("User-confirmed: \(WorkoutSession.number(entry.weight)) \(session.plan.unit.rawValue) × \(entry.reps) reps")
                        Text("Log tapped: \(entry.completedAt.formatted(date: .abbreviated, time: .standard))")
                    }
                    Text("Cross-workout comparisons need matching variation IDs, units and load conventions. This view describes this set only.").foregroundStyle(.secondary)
                }
            }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle("Observation").navigationBarTitleDisplayMode(.inline)
    }
}

struct ReviewView: View {
    let store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            LiftList {
                if let review = store.state.review {
                    Section("Analysis") { Text(review.analysis).textSelection(.enabled) }
                    Section(review.plan.title) {
                        ForEach(review.plan.exercises) { exercise in
                            MetricRow(title: exercise.name, value: "\(exercise.sets) × \(exercise.reps) · \(WorkoutSession.number(exercise.weight)) \(review.plan.unit.rawValue)")
                        }
                    }
                    Section { ObservationCollectionView(plan: review.plan) }
                    Section {
                        Button("Accept and send to watch") {
                            do { try store.acceptReview(); dismiss() } catch { store.error = error.localizedDescription }
                        }
                        Button("Discard proposal", role: .destructive) {
                            do { try store.discardReview(); dismiss() } catch { store.error = error.localizedDescription }
                        }
                    }
                }
            }.scrollContentBackground(.hidden).background(.black).navigationTitle("Next workout").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

struct SettingsView: View {
    let store: PhoneStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LiftPageHeading(title: "Preferences", detail: "Training, coaching and Watch controls.")
                LiftSection(title: "Training & coach") {
                    LiftSurface {
                        NavigationLink { TrainingProfileView(store: store) } label: { LiftMenuRow(title: "Training profile", symbol: "person.crop.circle") }
                        Divider().padding(.horizontal, 18)
                        NavigationLink { CoachingSettingsView(store: store) } label: {
                            LiftMenuRow(title: "Coach connection", symbol: "bubble.left.and.text.bubble.right", detail: store.state.mode.title)
                        }
                        Divider().padding(.horizontal, 18)
                        ShareLink(item: store.state.contextExport()) { LiftMenuRow(title: "Share coach context", symbol: "square.and.arrow.up", disclosure: false) }
                    }
                }
                LiftSection(title: "Your Watch") {
                    LiftSurface {
                        NavigationLink { WatchPreferencesView(store: store) } label: { LiftMenuRow(title: "Watch controls", symbol: "applewatch", detail: "Double tap, quick launch & reminders") }
                    }
                }
                LiftSection(title: "More") {
                    LiftSurface {
                        NavigationLink { MotionLibraryView(store: store) } label: { LiftMenuRow(title: "Motion test", symbol: "waveform.path", detail: "Optional experiment") }
                        Divider().padding(.horizontal, 18)
                        NavigationLink { DataInformationView(store: store) } label: { LiftMenuRow(title: "Data & connection", symbol: "internaldrive") }
                    }
                }
            }.padding(24).modifier(LiftContentEntrance())
        }.buttonStyle(.plain).background(.black).modifier(LiftRootChrome())
    }
}

struct CoachingSettingsView: View {
    let store: PhoneStore
    var body: some View {
        LiftForm {
            Section {
                ForEach(ConnectionMode.allCases, id: \.self) { mode in
                    Button {
                        do { try store.setMode(mode) } catch { store.error = error.localizedDescription }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(mode.title).font(LiftType.heading)
                                Text(mode == .existingChat ? "Share reports and import a reviewed plan." : "Run a separate review using Apple Shortcuts.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: store.state.mode == mode ? "checkmark.circle.fill" : "circle")
                                .accessibilityHidden(true)
                        }.foregroundStyle(.primary).padding(.vertical, 4)
                    }.accessibilityAddTraits(store.state.mode == mode ? .isSelected : [])
                }
            } header: { Text("How you work with your coach") }
              footer: { Text("A Shortcut does not inherit your existing chat. You accept every proposed workout before it becomes Today’s plan.") }
            Section {
                NavigationLink { ShortcutHelpView() } label: { LiftLabel("Set up review Shortcut", "arrow.triangle.branch") }
                NavigationLink { ReviewQueueView(store: store) } label: { LiftLabel("Coach reviews", "text.bubble") }
            }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle("Coach connection").navigationBarTitleDisplayMode(.inline)
    }
}

struct WatchPreferencesView: View {
    let store: PhoneStore
    var body: some View {
        LiftForm {
            Section {
                Toggle("Double tap to log", isOn: Binding(get: { store.state.doubleTapEnabled == true }, set: { value in do { try store.setDoubleTap(value) } catch { store.error = error.localizedDescription } }))
            } footer: { Text("Uses the visible Log set button on compatible Watches. Apple’s Double Tap setting must also be enabled. Rapid duplicate taps are ignored.") }
            Section("Quick launch") {
                Label("Add Little Lift to your watch face", systemImage: "applewatch")
                Text("Touch and hold your watch face, choose Edit, then add Little Lift to a complication slot.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Reminders & haptics") { Text("On Watch, open … → Preferences to change wrist haptics and rest reminders.").foregroundStyle(.secondary) }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle("Watch controls").navigationBarTitleDisplayMode(.inline)
    }
}

struct DataInformationView: View {
    let store: PhoneStore
    var body: some View {
        LiftList {
            Section("Stored on your devices") {
                Text("Workouts, routines and your training profile stay on your iPhone and Watch.")
                Text("Sharing a report or running a review sends only the context you choose. Little Lift has no hosted backend, analytics service or AI API key.").foregroundStyle(.secondary)
            }
            Section { DisclosureGroup("Connection details") { Text(store.connectionDetails).font(.caption.monospaced()).textSelection(.enabled) } }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle("Data & connection").navigationBarTitleDisplayMode(.inline)
    }
}

struct TrainingProfileView: View {
    let store: PhoneStore
    @State private var profile = ""
    @State private var saved = false
    var body: some View {
        LiftForm {
            Section {
                TextEditor(text: $profile).frame(minHeight: 220).accessibilityLabel("Training profile")
            } footer: {
                Text("Your goals, preferences and load conventions. Included when you share coach context or run a review. Add only what you want to share.")
                    .font(.footnote)
            }
            Section {
                Button(saved ? "Saved" : "Save profile") {
                    do { try store.setProfile(profile); saved = true } catch { store.error = error.localizedDescription }
                }
            }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle("Training profile").navigationBarTitleDisplayMode(.inline)
            .onAppear { profile = store.state.profile }
            .onChange(of: profile) { saved = false }
    }
}

struct ShortcutHelpView: View {
    private var preparedShortcut: URL? {
        let url = URL.documentsDirectory.appending(path: "Little Lift Review.shortcut")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    var body: some View {
        LiftList {
            if let preparedShortcut {
                Section("Prepared on this Mac") {
                    ShareLink(item: preparedShortcut) { Text("Open prepared review Shortcut") }
                    Text("Open the file in Shortcuts and add it. The three actions are already connected. Choose the ChatGPT extension when Apple asks for a model, or cancel if it is unavailable. No model is selected silently.").font(.caption)
                }
            }
            Section("One-time setup on iPhone") {
                Text("Create a Shortcut named Little Lift Review in Apple’s Shortcuts app.")
                Text("1. Add Little Lift’s Prepare Workout Review action. Its text includes your saved profile and recent workout logs.")
                Text("2. Add Use Model, choose the ChatGPT extension model, and use the previous action’s output as its prompt. Set Output to Text so the JSON passes to the next action. Enable Follow Up if you want to review or refine the answer there.")
                Text("3. Add Little Lift’s Save Workout Review action. Pass the model response into Review JSON.")
                Text("Run the Shortcut, then open Little Lift to review and accept the proposed plan.")
            }
            Section("Optional iOS 27 notification automation") {
                Text("Enable review notifications in Little Lift → Coach reviews. In Shortcuts, edit Little Lift Review → Automation → Notification; choose Little Lift and filter Title to Little Lift workout ready. Use Run Immediately only if the OS offers it. The notification is created after the phone saves the completed workout.")
                Text("Use Model may still require authentication, confirmation or an unlocked phone. If unattended execution is unavailable, use Run review Shortcut. Model failures stay visible in Coach reviews; cancel or retry there. Duplicate triggers are blocked by the durable review receipt.")
            }
            Section("What to expect") {
                Text("Connect your ChatGPT account in Apple Intelligence settings if you want to use it. Availability, limits, and confirmation prompts depend on Apple and your account.")
                Text("This does not append to your existing gym conversation. Use My existing chat for that workflow.")
                Text("If Use Model or ChatGPT is unavailable, use the copy-and-import workflow instead. You can also paste a review JSON response using Save Workout Review.")
            }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle("Shortcuts").navigationBarTitleDisplayMode(.inline)
    }
}
