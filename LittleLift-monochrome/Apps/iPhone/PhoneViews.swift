import SwiftUI
import UniformTypeIdentifiers

private struct SavedWorkoutReviewRoute: Hashable {
    let sessionID: UUID
}
private struct IncomingWorkoutFile: Identifiable {
    let id = UUID()
    let text: String?
    let backup: WorkoutBackup?
}

struct PhoneRootView: View {
    @Bindable var store: PhoneStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var incomingFile: IncomingWorkoutFile?
    var body: some View {
        TabView {
            Tab(L10n.s("Today"), systemImage: "dumbbell") { NavigationStack { TodayView(store: store) } }
            Tab(L10n.s("History"), systemImage: "list.bullet.rectangle") { NavigationStack { HistoryView(store: store) } }
            Tab(L10n.s("Progress"), systemImage: "chart.bar.xaxis") { NavigationStack { TrainingProgressView(store: store) } }
            Tab(L10n.s("Routines"), systemImage: "square.stack") { NavigationStack { RoutineLibraryView(store: store) } }
            Tab(L10n.s("Settings"), systemImage: "slider.horizontal.3") { NavigationStack { SettingsView(store: store) } }
        }
        .sheet(isPresented: $store.showingReviewQueue, onDismiss: { store.openedReviewSessionID = nil }) {
            NavigationStack {
                Group {
                    if let session = store.state.effectiveSessions.first(where: { $0.id == store.openedReviewSessionID }) {
                        WorkoutEvidenceReviewView(session: session, store: store)
                    } else { ReviewQueueView(store: store) }
                }.toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.s("Close")) { store.showingReviewQueue = false } } }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.sendToWatch() } }
        .sheet(item: $incomingFile) { file in
            if let backup = file.backup {
                NavigationStack { WorkoutBackupView(store: store, initialBackup: backup)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.s("Close")) { incomingFile = nil } } }
                }
            } else { SmartImportView(store: store, initialText: file.text ?? "") }
        }
        .onOpenURL { url in
            do {
                guard incomingFile == nil else { throw WorkoutError.invalidState(L10n.s("Finish or close the current import before opening another file.")) }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try InputBoundary.read(url, maximumBytes: WorkoutBackup.maximumBytes)
                if data.first(where: { ![9, 10, 13, 32].contains($0) }) == 123 { try JSONBoundary.validate(data) }
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["format"] as? String == "littlelift.workout-backup" {
                    incomingFile = IncomingWorkoutFile(text: nil, backup: try WorkoutBackup.decode(data))
                } else { incomingFile = IncomingWorkoutFile(text: try WorkoutFileImport.text(from: data), backup: nil) }
            } catch { store.error = error.localizedDescription }
        }
        .alert(L10n.s("Couldn’t save"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button(L10n.s("OK")) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct TodayView: View {
    let store: PhoneStore
    @Environment(\.dynamicTypeSize) private var dynamicType
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
                    reviewStatus
                    LiftSection(title: L10n.s("Your exercises")) {
                        LiftSurface {
                            ForEach(plan.exercises) { exercise in
                                VStack(alignment: .leading, spacing: 0) {
                                    LiftExerciseRow(exercise: exercise, unit: plan.unit,
                                                    number: (plan.exercises.firstIndex(where: { $0.id == exercise.id }) ?? 0) + 1)
                                        .padding(18)
                                    if let previous = Progression.lastResult(for: exercise, unit: plan.unit, sessions: store.state.effectiveSessions) {
                                        NavigationLink { SessionDetailView(session: previous.session) } label: {
                                            HStack(spacing: 8) {
                                                Text(L10n.s("Last: \(WorkoutSession.number(previous.entry.weight)) \(plan.unit.rawValue) × \(previous.entry.reps)"))
                                                Spacer(minLength: 8)
                                                Text(L10n.s("View set")); LiftChevron()
                                            }.font(.caption).foregroundStyle(.secondary)
                                                .padding(.horizontal, 18).frame(minHeight: 44)
                                        }.accessibilityLabel(L10n.s("Last matching final set, \(WorkoutSession.number(previous.entry.weight)) \(plan.unit.rawValue), \(previous.entry.reps) repetitions. View workout record."))
                                    }
                                    if exercise.id != plan.exercises.last?.id { Divider().padding(.horizontal, 18) }
                                }
                            }
                        }
                    }
                    LiftSurface {
                        NavigationLink { TimePlanningView(store: store) } label: {
                            LiftMenuRow(title: L10n.s("Fit your available time"), symbol: "clock")
                        }
                        Divider().padding(.horizontal, 18)
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 20) {
                                connectionActions
                                ObservationCollectionView(plan: plan)
                            }.padding(.horizontal, 18).padding(.bottom, 12)
                        } label: {
                            LiftMenuRow(title: L10n.s("Coach & sharing"), symbol: "bubble.left.and.text.bubble.right", disclosure: false)
                        }.padding(.trailing, 18)
                    }
                } else {
                    LiftPageHeading(title: L10n.s("Your next workout"), detail: L10n.s("Bring a workout from your coach, a screenshot or your own notes."))
                    LiftSurface {
                        Button { importing = true } label: { LiftMenuRow(title: L10n.s("Import a workout"), symbol: "square.and.arrow.down", detail: L10n.s("Review and edit before saving")) }
                        if !store.state.routineLibrary.isEmpty {
                            Divider().padding(.horizontal, 18)
                            Button { choosing = true } label: { LiftMenuRow(title: L10n.s("Choose a saved routine"), symbol: "square.stack") }
                        }
                    }
                    Button(L10n.s("Try a generic example")) {
                        do { var example = try PlanImport.parse(PlanImport.example); example.practice = true; try store.acceptImportedPlan(example) } catch { store.error = error.localizedDescription }
                    }.font(.subheadline).frame(minHeight: 44)
                    NavigationLink(L10n.s("Start here")) { GettingStartedView(store: store) }.frame(minHeight: 44)
                    connectionActions
                    reviewStatus
                }
                NavigationLink { ReviewQueueView(store: store) } label: {
                    HStack { Text(L10n.s("Workout reviews")).font(.subheadline); Spacer(); LiftChevron() }.frame(minHeight: 44)
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
        .navigationDestination(for: SavedWorkoutReviewRoute.self) { route in
            if let session = store.state.effectiveSessions.first(where: { $0.id == route.sessionID }) {
                WorkoutEvidenceReviewView(session: session, store: store)
            }
        }
        .sheet(isPresented: $choosing) { WorkoutChooserView(store: store) }
        .sheet(item: $editing) { plan in
            NavigationStack {
                WorkoutEditorView(store: store, initial: WorkoutDraft(plan: plan), routineID: store.state.routineLibrary.first(where: { $0.plan == plan })?.id, useToday: true) { editing = nil }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.s("Cancel")) { editing = nil } } }
            }.tint(.white).presentationBackground(.black)
        }
        .sheet(isPresented: $importing) { SmartImportView(store: store) }
        .sheet(isPresented: $reviewing) { ReviewView(store: store) }
        .sensoryFeedback(trigger: copies) { _, _ in PhoneStore.shared.state.comfort?.haptics == false ? nil : .success }
    }

    @ViewBuilder private var reviewStatus: some View {
        if store.state.review != nil {
            Button { reviewing = true } label: {
                LiftSurface { LiftMenuRow(title: L10n.s("A new workout to review"), symbol: "text.bubble", detail: L10n.s("Changes need your acceptance")) }
            }
        }
        if let latest = store.state.effectiveSessions.first {
            let job = store.state.reviewQueue.first { $0.id == latest.id }
            NavigationLink(value: SavedWorkoutReviewRoute(sessionID: latest.id)) {
                LiftSurface {
                    LiftMenuRow(title: job?.result != nil && job?.outdatedAt == nil ? L10n.s("Coach response ready") : L10n.s("Workout saved · review ready"),
                        symbol: "checkmark.circle", detail: latest.plan.title + " · " + latest.startedAt.formatted(date: .abbreviated, time: .omitted))
                }
            }.accessibilityIdentifier("today.latestReview")
        }
    }

    private var sendButton: some View {
        Button { store.sendToWatch() } label: {
            Label(store.isSyncing ? L10n.s("Sending…") : (store.state.todayReceivedOnWatch ? L10n.s("Send again") : L10n.s("Send to Watch")), systemImage: "applewatch")
                .padding(.horizontal, 10).padding(.vertical, 3)
        }.buttonStyle(QuietButtonStyle(prominent: true))
            .disabled(store.isSyncing || store.state.plan == nil)
    }

    private var importButton: some View {
        Button { importing = true } label: { Label(L10n.s("Import"), systemImage: "plus").padding(.horizontal, 10).padding(.vertical, 3) }
            .buttonStyle(QuietButtonStyle()).accessibilityLabel(L10n.s("Import workout"))
    }

    private func workoutHeader(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            LiftEyebrow(text: Date.now.formatted(.dateTime.weekday(.wide).month().day().locale(Locale(identifier: L10n.language))))
            LiftPageHeading(title: plan.title)
            HStack(spacing: 16) {
                LiftStat(value: String(plan.exercises.count), label: L10n.s("Exercises"))
                LiftStat(value: String(plan.totalSets), label: plan.exercises.contains { $0.kind != .strength } ? L10n.s("Sets / segments") : L10n.s("Sets"))
                if plan.exercises.contains(where: { $0.kind == .strength || $0.activity?.additionalLoad != nil }) { LiftStat(value: plan.unit.rawValue, label: L10n.s("Load unit")) }
            }
            let actionLayout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            actionLayout {
                Button { choosing = true } label: { Label(L10n.s("Change workout"), systemImage: "arrow.left.arrow.right") }
                    .buttonStyle(QuietButtonStyle())
                Button { editing = plan } label: { Label(L10n.s("Edit"), systemImage: "pencil").padding(.horizontal, 12) }
                    .buttonStyle(QuietButtonStyle()).fixedSize(horizontal: !dynamicType.isAccessibilitySize, vertical: false)
            }
            TodayDeliveryView(store: store)
            if let slot = store.state.weeklySchedule.first(where: { $0.weekday == Calendar.current.component(.weekday, from: Date()) }),
               let routine = store.state.routineLibrary.first(where: { $0.id == slot.routineID }), routine.plan.id != plan.id {
                Button { choosing = true } label: {
                    Label(L10n.s("Scheduled: \(routine.plan.title)"), systemImage: "calendar").font(.caption).frame(minHeight: 44)
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
                } label: { Label(copies > 0 ? L10n.s("Prompt copied") : L10n.s("Copy coaching prompt"), systemImage: copies > 0 ? "checkmark" : "doc.on.doc") }.buttonStyle(QuietButtonStyle())
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : LiftMotion.feedback, value: copies > 0)
            } else {
                Button(L10n.s("Run review Shortcut")) {
                    var parts = URLComponents(); parts.scheme = "shortcuts"; parts.host = "run-shortcut"
                    parts.queryItems = [URLQueryItem(name: "name", value: "Little Lift Review")]
                    if let url = parts.url { openURL(url) }
                }.buttonStyle(QuietButtonStyle())
                NavigationLink(L10n.s("Set up the Shortcut")) { ShortcutHelpView() }.font(.subheadline)
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
                    Text(L10n.s("Copy the coaching prompt into your gym chat, then paste its JSON reply here. You’ll review the exercises before saving."))
                    ShareLink(item: PlanImport.coachingPrompt) { Label(L10n.s("Share coaching prompt"), systemImage: "square.and.arrow.up") }
                }
                Section(L10n.s("Workout JSON")) {
                    PasteButton(payloadType: String.self) { strings in text = strings.joined(separator: "\n"); preview = nil }
                    TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(height: 220)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .accessibilityLabel(L10n.s("Workout JSON"))
                    Button(L10n.s("Choose a JSON or text file")) { importingFile = true }
                    Button(L10n.s("Preview workout")) {
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
                                Text(exercise.prescription(unit: preview.unit))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ObservationCollectionView(plan: preview)
                        Button(L10n.s("Save and send to watch")) {
                            do { try store.acceptImportedPlan(preview); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(.black)
            .onChange(of: text) { preview = nil }
            .navigationTitle(L10n.s("Import workout")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.s("Cancel")) { dismiss() } } }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.json, .plainText]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= 64_000 else { throw WorkoutError.invalidInput(L10n.s("Choose a file smaller than 64 KB.")) }
                    let data = try InputBoundary.read(url, maximumBytes: 64_000)
                    guard let value = String(data: data, encoding: .utf8) else { throw WorkoutError.invalidInput(L10n.s("Choose a UTF-8 text file.")) }
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
                LiftPageHeading(title: L10n.s("Your training"), detail: L10n.s("Every set, kept in one place."))
                if !store.state.effectiveSessions.isEmpty {
                    HStack {
                        LiftStat(value: String(store.state.effectiveSessions.count), label: L10n.s("Recorded workouts"))
                        LiftStat(value: String(store.state.effectiveSessions.reduce(0) { $0 + $1.loggedWorkCount }), label: L10n.s("Sets / segments logged"))
                    }
                    LiftSection(title: L10n.s("Recorded with Little Lift")) {
                        LazyVStack(spacing: 12) {
                            ForEach(store.state.effectiveSessions) { session in
                                NavigationLink { SessionDetailView(session: session) } label: {
                                    LiftSurface {
                                        HStack(alignment: .top, spacing: 20) {
                                            VStack(spacing: 4) {
                                                Text(session.startedAt, format: .dateTime.day()).font(.system(.title2, design: .serif))
                                                Text(session.startedAt, format: .dateTime.month(.abbreviated)).font(.caption).foregroundStyle(.secondary)
                                            }.frame(minWidth: 36)
                                            VStack(alignment: .leading, spacing: 9) {
                                                Text(session.plan.title).font(LiftType.heading)
                                                Text(L10n.s("\(session.loggedWorkCount) sets / segments · \(Int(session.duration / 60)) min")).font(.caption).foregroundStyle(.secondary)
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
                    LiftSection(title: L10n.s("Imported · user-confirmed")) {
                        LiftSurface {
                            ForEach(store.state.externalHistory) { record in
                                NavigationLink {
                                    ScrollView { Text(record.report()).textSelection(.enabled).padding(24) }.background(.black).navigationTitle(L10n.s("Imported record"))
                                } label: { LiftMenuRow(title: record.title, symbol: "doc.text", detail: String(record.date.prefix(10))) }
                                if record.id != store.state.externalHistory.last?.id { Divider().padding(.horizontal, 18) }
                            }
                        }
                    }
                }
                if store.state.effectiveSessions.isEmpty && store.state.externalHistory.isEmpty {
                    LiftSurface { VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "list.bullet.rectangle").font(.title2.weight(.light))
                        Text(L10n.s("Ready for your first workout")).font(LiftType.title)
                        Text(L10n.s("Finish a workout on Watch. Your logged sets will appear here when your devices connect.")).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(24) }
                }
                NavigationLink { HistoryImportView(store: store) } label: {
                    LiftSurface { LiftMenuRow(title: L10n.s("Import previous workouts"), symbol: "square.and.arrow.down", detail: L10n.s("Kept separate from app recordings")) }
                }
            }.padding(24).modifier(LiftContentEntrance())
        }.buttonStyle(.plain).background(.black).modifier(LiftRootChrome())
    }
}

struct SessionDetailView: View {
    private let original: WorkoutSession
    private let store = PhoneStore.shared
    private var session: WorkoutSession { store.state.effectiveSession(original.id) ?? original }
    init(session: WorkoutSession) { original = session }
    @State private var copies = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    LiftEyebrow(text: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    LiftPageHeading(title: session.plan.title)
                    HStack {
                        LiftStat(value: "\(session.loggedWorkCount) / \(session.plan.totalSets)", label: L10n.s("Sets / segments logged"))
                        LiftStat(value: "\(Int(session.duration / 60)) min", label: L10n.s("Session duration"))
                    }
                }
                NavigationLink { WorkoutEvidenceReviewView(session: session, store: PhoneStore.shared) } label: {
                    LiftSurface { LiftMenuRow(title: L10n.s("Automatic review"), symbol: "checkmark.circle", detail: L10n.s("Targets, actual values and comparable earlier sets")) }
                }
                if !session.entries.isEmpty {
                    NavigationLink { WorkoutCorrectionView(store: store, sessionID: session.id) } label: {
                        LiftSurface { LiftMenuRow(title: L10n.s("Correct record"), symbol: "pencil", detail: L10n.s("Original values are preserved")) }
                    }
                }
                if let corrections = session.correctionSummary {
                    DisclosureGroup(L10n.s("Original values & corrections")) { Text(corrections).font(.caption).textSelection(.enabled) }
                }
                LiftSection(title: L10n.s("Recorded work")) {
                    ForEach(session.executionExercises) { exercise in
                        LiftSurface {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(exercise.name).font(.body)
                                Text(L10n.s("Target · \(exercise.prescription(unit: session.plan.unit))"))
                                    .font(.caption).foregroundStyle(.secondary)
                                Divider()
                                let entries = session.entries.filter { $0.exerciseID == exercise.id }
                                if let result = session.activities?.first(where: { $0.exerciseID == exercise.id }) { Text(result.summary(unit: exercise.activity?.distanceUnit ?? .km)).font(.callout) }
                                else if entries.isEmpty { Text(L10n.s("Not completed")).font(.subheadline).foregroundStyle(.secondary) }
                                ForEach(entries) { entry in
                                    MetricRow(title: L10n.s("Set \(entry.setNumber)"), value: "\(WorkoutSession.number(entry.weight)) \(session.plan.unit.rawValue) × \(entry.reps)")
                                }
                            }.padding(18)
                        }
                    }
                }
                if !session.plan.observationRequests.isEmpty {
                    LiftSection(title: L10n.s("Coach observations")) {
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
                    DisclosureGroup(L10n.s("Changes & original prescription")) {
                        ForEach(changes) { Text($0.detail).font(.caption) }
                        ForEach(session.plan.exercises) { Text(L10n.s("Original: \($0.name) · \($0.prescription(unit: session.plan.unit))")).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let proposal = session.nextSessionProposal {
                    NavigationLink(L10n.s("Review substitution for next time")) { WorkoutEditorView(store: PhoneStore.shared, initial: WorkoutDraft(plan: proposal), routineID: nil) }
                }
                LiftSurface {
                    ShareLink(item: session.report()) { LiftMenuRow(title: L10n.s("Share workout report"), symbol: "square.and.arrow.up", disclosure: false) }
                    Divider().padding(.horizontal, 18)
                    Button { UIPasteboard.general.string = session.report(); copies += 1 } label: {
                        LiftMenuRow(title: copies > 0 ? L10n.s("Report copied") : L10n.s("Copy for my gym chat"), symbol: copies > 0 ? "checkmark" : "doc.on.doc", disclosure: false)
                    }
                }
            }.padding(24).modifier(LiftContentEntrance())
        }.buttonStyle(.plain).background(.black).navigationTitle(L10n.s("Workout record")).navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(trigger: copies) { _, _ in PhoneStore.shared.state.comfort?.haptics == false ? nil : .success }
    }
}

struct ObservationCollectionView: View {
    let plan: WorkoutPlan
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.s("What will be collected")).font(.callout.weight(.medium))
            if plan.observationRequests.isEmpty {
                Text(L10n.s("Actual loads and repetitions for strength; explicit Start/Pause/Done events for timed activities. Optional machine readings stay separate from targets. No additional coach observations requested."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(plan.observationRequests) { request in
                    Text(request.collectionDescription(in: plan)).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(L10n.s("Stored on your devices. Included when you share a report or run your review Shortcut."))
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
                Section(L10n.s("Set context")) {
                    Text(L10n.s("Prescribed: \(WorkoutSession.number(exercise.weight)) \(session.plan.unit.rawValue) × \(exercise.reps) reps"))
                    Text(L10n.s("Load convention: \(exercise.loadConvention?.label ?? L10n.s("unspecified"))"))
                    if let entry = session.entries.first(where: { $0.id == evidence.setID }) {
                        Text(L10n.s("User-confirmed: \(WorkoutSession.number(entry.weight)) \(session.plan.unit.rawValue) × \(entry.reps) reps"))
                        Text(L10n.s("Log tapped: \(entry.completedAt.formatted(date: .abbreviated, time: .standard))"))
                    }
                    Text(L10n.s("Cross-workout comparisons need matching variation IDs, units and load conventions. This view describes this set only.")).foregroundStyle(.secondary)
                }
            }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle(L10n.s("Observation")).navigationBarTitleDisplayMode(.inline)
    }
}

struct ReviewView: View {
    let store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            LiftList {
                if let review = store.state.review {
                    Section(L10n.s("Analysis")) { Text(review.analysis).textSelection(.enabled) }
                    Section(review.plan.title) {
                        ForEach(review.plan.exercises) { exercise in
                            MetricRow(title: exercise.name, value: exercise.prescription(unit: review.plan.unit))
                        }
                    }
                    Section { ObservationCollectionView(plan: review.plan) }
                    Section {
                        Button(L10n.s("Accept and send to watch")) {
                            do { try store.acceptReview(); dismiss() } catch { store.error = error.localizedDescription }
                        }
                        Button(L10n.s("Discard proposal")) {
                            do { try store.discardReview(); dismiss() } catch { store.error = error.localizedDescription }
                        }
                    }
                }
            }.scrollContentBackground(.hidden).background(.black).navigationTitle(L10n.s("Next workout")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.s("Close")) { dismiss() } } }
        }
    }
}

struct SettingsView: View {
    let store: PhoneStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LiftPageHeading(title: L10n.s("Preferences"), detail: L10n.s("Training, coaching and Watch controls."))
                LiftSection(title: L10n.s("Training & coach")) {
                    LiftSurface {
                        NavigationLink { TrainingProfileView(store: store) } label: { LiftMenuRow(title: L10n.s("Training profile"), symbol: "person.crop.circle") }
                        Divider().padding(.horizontal, 18)
                        NavigationLink { CoachingSettingsView(store: store) } label: {
                            LiftMenuRow(title: L10n.s("Coach connection"), symbol: "bubble.left.and.text.bubble.right", detail: store.state.mode.title)
                        }
                        Divider().padding(.horizontal, 18)
                        NavigationLink { CoachContextView(store: store) } label: { LiftMenuRow(title: L10n.s("Review coach context"), symbol: "square.and.arrow.up") }
                    }
                }
                LiftSection(title: L10n.s("Help & preferences")) {
                    LiftSurface {
                        NavigationLink { GettingStartedView(store: store) } label: { LiftMenuRow(title: L10n.s("Start here"), symbol: "checklist") }
                        NavigationLink { ExerciseHelpView() } label: { LiftMenuRow(title: L10n.s("Exercise help"), symbol: "questionmark.circle") }
                        NavigationLink { ComfortSettingsView(store: store) } label: { LiftMenuRow(title: L10n.s("Training preferences"), symbol: "slider.horizontal.3") }
                        NavigationLink { WeeklyHabitView(store: store) } label: { LiftMenuRow(title: L10n.s("Weekly goal"), symbol: "calendar") }
                    }
                }
                LiftSection(title: L10n.s("Your Watch")) {
                    LiftSurface {
                        NavigationLink { WatchPreferencesView(store: store) } label: { LiftMenuRow(title: L10n.s("Watch controls"), symbol: "applewatch", detail: L10n.s("Double tap, quick launch & reminders")) }
                    }
                }
                LiftSection(title: L10n.s("More")) {
                    LiftSurface {
                        NavigationLink { MotionLibraryView(store: store) } label: { LiftMenuRow(title: L10n.s("Motion test"), symbol: "waveform.path", detail: L10n.s("Optional experiment")) }
                        Divider().padding(.horizontal, 18)
                        NavigationLink { WorkoutBackupView(store: store) } label: { LiftMenuRow(title: L10n.s("Backups"), symbol: "externaldrive", detail: L10n.s("Export or restore your training records")) }
                        Divider().padding(.horizontal, 18)
                        NavigationLink { DataInformationView(store: store) } label: { LiftMenuRow(title: L10n.s("Data & connection"), symbol: "internaldrive") }
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
                                Text(mode == .existingChat ? L10n.s("Share reports and import a reviewed plan.") : L10n.s("Run a separate review using Apple Shortcuts."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: store.state.mode == mode ? "checkmark.circle.fill" : "circle")
                                .accessibilityHidden(true)
                        }.foregroundStyle(.primary).padding(.vertical, 4)
                    }.accessibilityAddTraits(store.state.mode == mode ? .isSelected : [])
                }
            } header: { Text(L10n.s("How you work with your coach")) }
              footer: { Text(L10n.s("A Shortcut does not inherit your existing chat. You accept every proposed workout before it becomes Today’s plan.")) }
            Section {
                NavigationLink { ShortcutHelpView() } label: { LiftLabel(L10n.s("Set up review Shortcut"), "arrow.triangle.branch") }
                NavigationLink { ReviewQueueView(store: store) } label: { LiftLabel(L10n.s("Coach reviews"), "text.bubble") }
            }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle(L10n.s("Coach connection")).navigationBarTitleDisplayMode(.inline)
    }
}

struct WatchPreferencesView: View {
    let store: PhoneStore
    var body: some View {
        LiftForm {
            Section {
                Toggle(L10n.s("Double tap to log"), isOn: Binding(get: { store.state.doubleTapEnabled == true }, set: { value in do { try store.setDoubleTap(value) } catch { store.error = error.localizedDescription } }))
            } footer: { Text(L10n.s("Uses the visible Log set button on compatible Watches. Apple’s Double Tap setting must also be enabled. Rapid duplicate taps are ignored.")) }
            Section(L10n.s("Quick launch")) {
                Label(L10n.s("Add Little Lift to your watch face"), systemImage: "applewatch")
                Text(L10n.s("Touch and hold your watch face, choose Edit, then add Little Lift to a complication slot.")).font(.callout).foregroundStyle(.secondary)
            }
            Section(L10n.s("Reminders & haptics")) { Text(L10n.s("On Watch, open … → Preferences to change wrist haptics and rest reminders.")).foregroundStyle(.secondary) }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle(L10n.s("Watch controls")).navigationBarTitleDisplayMode(.inline)
    }
}

struct DataInformationView: View {
    let store: PhoneStore
    var body: some View {
        LiftList {
            Section(L10n.s("Stored on your devices")) {
                Text(L10n.s("Workouts, routines and your training profile stay on your iPhone and Watch."))
                Text(L10n.s("Sharing a report or running a review sends only the context you choose. Little Lift has no hosted backend, analytics service or AI API key.")).foregroundStyle(.secondary)
            }
            NavigationLink(L10n.s("Backups")) { WorkoutBackupView(store: store) }
            Section { DisclosureGroup(L10n.s("Connection details")) { Text(store.connectionDetails).font(.caption.monospaced()).textSelection(.enabled) } }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle(L10n.s("Data & connection")).navigationBarTitleDisplayMode(.inline)
    }
}

struct TrainingProfileView: View {
    let store: PhoneStore
    @State private var profile = ""
    @State private var saved = false
    var body: some View {
        LiftForm {
            Section {
                TextEditor(text: $profile).frame(minHeight: 220).accessibilityLabel(L10n.s("Training profile"))
            } footer: {
                Text(L10n.s("Your goals, preferences and load conventions. Included when you share coach context or run a review. Add only what you want to share."))
                    .font(.footnote)
            }
            Section {
                Button(saved ? L10n.s("Saved") : L10n.s("Save profile")) {
                    do { try store.setProfile(profile); saved = true } catch { store.error = error.localizedDescription }
                }
            }
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle(L10n.s("Training profile")).navigationBarTitleDisplayMode(.inline)
            .onAppear { profile = store.state.profile }
            .onChange(of: profile) { saved = false }
    }
}

struct ShortcutHelpView: View {
    private let store = PhoneStore.shared
    @Environment(\.openURL) private var openURL
    private var preparedCheck: URL? {
        let url = URL.documentsDirectory.appending(path: "Little Lift Connection Check.shortcut")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    private var preparedShortcut: URL? {
        let url = URL.documentsDirectory.appending(path: "Little Lift Review.shortcut")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    var body: some View {
        LiftList {
            Section(L10n.s("Check the connection")) {
                Text(L10n.s("Uses a fictional set. Your profile, workouts and current plan stay on this device. A returned response confirms the round trip, not coaching quality or automatic execution.")).font(.subheadline)
                if let preparedCheck {
                    ShareLink(item: preparedCheck) { LiftLabel(L10n.s("Add test Shortcut"), "arrow.down.document") }
                }
                Button { openURL(URL(string: "shortcuts://run-shortcut?name=Little%20Lift%20Connection%20Check")!) } label: {
                    LiftLabel(L10n.s("Run generic connection check"), "arrow.triangle.2.circlepath")
                }
                if let check = store.state.coachConnectionCheck {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        if check.receivedAt != nil {
                            Label(L10n.s("Response received · history unchanged"), systemImage: "checkmark.circle").font(.subheadline)
                        } else if check.isWaiting(now: context.date) {
                            Text(L10n.s("Waiting for the response…")).font(.subheadline)
                            Button(L10n.s("Cancel connection check")) { do { try store.cancelConnectionCheck() } catch { store.error = error.localizedDescription } }
                        } else {
                            Text(L10n.s("No response confirmed. Check Shortcuts permissions and run the test again.")).font(.subheadline)
                        }
                    }
                }
                Text(L10n.s("Add the test Shortcut first. It uses Prepare Coach Connection Check → Use Model with ChatGPT → Save Workout Review. Apple may ask you to allow the actions. Opening Shortcuts alone does not pass the test.")).font(.caption).foregroundStyle(.secondary)
            }
            if let preparedShortcut {
                Section(L10n.s("Prepared on this Mac")) {
                    ShareLink(item: preparedShortcut) { Text(L10n.s("Open prepared review Shortcut")) }
                    Text(L10n.s("Open the file in Shortcuts and add it. The three actions are connected and ChatGPT is selected explicitly. Enable Apple’s ChatGPT extension if needed. There is no automatic switch to another provider.")).font(.caption)
                }
            }
            Section(L10n.s("One-time setup on iPhone")) {
                Text(L10n.s("Create a Shortcut named Little Lift Review in Apple’s Shortcuts app."))
                Text(L10n.s("1. Add Little Lift’s Prepare Workout Review action. Its text includes your saved profile and recent workout logs."))
                Text(L10n.s("2. Add Use Model, choose the ChatGPT extension model, and use the previous action’s output as its prompt. Set Output to Text so the JSON passes to the next action. Enable Follow Up if you want to review or refine the answer there."))
                Text(L10n.s("3. Add Little Lift’s Save Workout Review action. Pass the model response into Review JSON."))
                Text(L10n.s("Run the Shortcut, then open Little Lift to review and accept the proposed plan."))
            }
            Section(L10n.s("Optional iOS 27 notification automation")) {
                Text(L10n.s("Enable review notifications in Little Lift → Coach reviews. In Shortcuts, edit Little Lift Review → Automation → Notification; choose Little Lift and filter Title to contain Little Lift. Use Run Immediately only if the OS offers it. The notification is created after the phone saves the completed workout."))
                Text(L10n.s("Use Model may still require authentication, confirmation or an unlocked phone. If unattended execution is unavailable, use Run review Shortcut. Model failures stay visible in Coach reviews; cancel or retry there. Duplicate triggers are blocked by the durable review receipt."))
            }
            Section(L10n.s("What to expect")) {
                Text(L10n.s("Connect your ChatGPT account in Apple Intelligence settings if you want to use it. Availability, limits, and confirmation prompts depend on Apple and your account."))
                Text(L10n.s("This does not append to your existing gym conversation. Use My existing chat for that workflow."))
                Text(L10n.s("If Use Model or ChatGPT is unavailable, use the copy-and-import workflow instead. You can also paste a review JSON response using Save Workout Review."))
            }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle(L10n.s("Shortcuts")).navigationBarTitleDisplayMode(.inline)
    }
}
