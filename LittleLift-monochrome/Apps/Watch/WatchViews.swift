import SwiftUI

/// watchOS text styles have larger defaults than their iPhone counterparts.
/// Explicit base sizes keep the small screen calm while still scaling with
/// the user's Dynamic Type preference. Touch targets are sized separately.
enum WatchTextRole {
    case title, body, secondary, caption
    var size: CGFloat {
        switch self { case .title: 17; case .body: 15; case .secondary: 13; case .caption: 12 }
    }
    var relativeStyle: Font.TextStyle {
        switch self { case .title: .headline; case .body: .body; case .secondary: .subheadline; case .caption: .caption2 }
    }
}

struct WatchTextStyle: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    init(_ role: WatchTextRole, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: role.size, relativeTo: role.relativeStyle)
        self.weight = weight
        design = .default
    }
    func body(content: Content) -> some View { content.font(.system(size: size, weight: weight, design: design)) }
}

extension View {
    func watchText(_ role: WatchTextRole, weight: Font.Weight = .regular) -> some View {
        modifier(WatchTextStyle(role, weight: weight))
    }
}

struct WatchRootView: View {
    @Bindable var store: WatchStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if let session = store.state.session {
                    switch session.phase {
                    case .active: SetView(store: store, session: session)
                    case .resting: RestView(store: store, session: session)
                    case .completed: SummaryView(store: store, session: session)
                    }
                } else { WatchTodayView(store: store) }
            }
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.presentedSheet = .options } label: {
                        Image(systemName: "ellipsis").foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Workout options")
                }
            }
            .sheet(item: $store.presentedSheet) { sheet in
                switch sheet {
                case .options: WatchOptionsView(store: store)
                case .motion:
                    NavigationStack {
                        MotionCaptureView(store: store)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { store.presentedSheet = nil } } }
                    }
                case .effort:
                    if let session = store.state.session, let request = session.pendingEffort {
                        EffortRatingView(store: store, request: request, plan: session.plan)
                    }
                }
            }
            .alert("Couldn’t save", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.foreground() } }
        .onAppear { store.foreground() }
        .onOpenURL { url in
            if url.scheme == "littlelift", url.host == "motion", store.state.motionOptIn == true { store.presentedSheet = .motion }
        }
    }
}

/// The action area is outside the adaptable content, so it cannot scroll away.
/// Normal-sized content fits directly. Larger accessibility text can scroll
/// within the remaining space without pushing the action below the screen.
struct WatchPage<Content: View, Actions: View>: View {
    let content: Content
    let actions: Actions

    init(@ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 6) {
            ViewThatFits(in: .vertical) {
                content.fixedSize(horizontal: false, vertical: true)
                ScrollView { content.padding(.vertical, 2) }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
            .modifier(LiftContentEntrance())
            actions
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .padding(.horizontal, 4)
        // watchOS reserves a large bottom inset for scrolling lists. These
        // pages have their own fixed controls and need that space on 46 mm.
        .padding(.bottom, 16)
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

struct WatchTodayView: View {
    let store: WatchStore
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 22

    var body: some View {
        WatchPage {
            VStack(alignment: .leading, spacing: 8) {
                if let plan = store.state.plan {
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell").accessibilityHidden(true)
                        Text("TODAY").tracking(1.5)
                    }.watchText(.caption).foregroundStyle(.secondary)
                    Text(plan.title).font(.system(size: titleSize, weight: .regular, design: .serif)).lineLimit(2)
                    Text(LiftCopy.workoutSummary(plan))
                        .watchText(.secondary).foregroundStyle(.secondary)
                    if let first = plan.exercises.first {
                        Divider().padding(.vertical, 2)
                        Text("First · \(first.name)").watchText(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                } else {
                    Text("No workout yet").watchText(.title)
                    Text("Open Little Lift on your paired iPhone and import a plan.")
                        .watchText(.secondary).foregroundStyle(.secondary)
                    if !store.syncNote.isEmpty {
                        Text(store.syncNote).watchText(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            if store.state.plan != nil {
                Button { store.perform { try store.start() } } label: { Label("Start workout", systemImage: "play.fill") }
                    .buttonStyle(QuietButtonStyle(prominent: true))
            } else {
                Button(store.isSyncing ? "Syncing…" : "Sync with iPhone") { store.retrySync() }
                    .buttonStyle(QuietButtonStyle()).disabled(store.isSyncing)
            }
        }
    }
}

struct SetView: View {
    @Bindable var store: WatchStore
    let session: WorkoutSession

    var body: some View {
        WatchPage {
            VStack(spacing: 0) {
                EffortInvitation(store: store, session: session)
                if let exercise = session.currentExercise {
                    WorkoutSetPanel(exercise: exercise, unit: session.plan.unit, setNumber: session.currentSetNumber,
                                weight: $store.draftWeight, reps: $store.draftReps, haptics: store.state.haptics)
                }
            }
        } actions: {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let allowed = LogActionGuard.allows(session: session, presentedSheet: store.presentedSheet != nil, now: context.date)
                Button { store.perform { try store.logSet() } } label: { Label("Log set", systemImage: "checkmark") }.buttonStyle(QuietButtonStyle(prominent: true))
                    .disabled(!allowed)
                    .handGestureShortcut(.primaryAction, isEnabled: allowed && store.state.doubleTapEnabled == true)
            }
        }
        .id(session.currentExercise?.id)
    }
}

struct WorkoutSetPanel: View {
    let exercise: ExercisePlan
    let unit: WeightUnit
    let setNumber: Int
    @Binding var weight: Double
    @Binding var reps: Double
    let haptics: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 0) {
                Text(exercise.name).watchText(.body).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Set \(setNumber) of \(exercise.sets)").watchText(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    GeometryReader { proxy in
                        Capsule().fill(.white.opacity(0.16))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.65)).frame(width: proxy.size.width * Double(setNumber - 1) / Double(max(1, exercise.sets)))
                            }
                    }.frame(width: 32, height: 2).accessibilityHidden(true)
                }
            }
            HStack(spacing: 6) {
                WatchNumberField(title: unit.rawValue.uppercased(), value: $weight,
                                 step: unit == .kg ? 0.5 : 1, range: 0...1000, haptics: haptics)
                WatchNumberField(title: "REPS", value: $reps, step: 1, range: 1...200, haptics: haptics)
            }
        }
    }
}

struct WatchNumberField: View {
    let title: String
    @Binding var value: Double
    let step: Double
    let range: ClosedRange<Double>
    let haptics: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var numberSize: CGFloat = 26

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value, format: .number.precision(.fractionLength(0...1)))
                    .font(.system(size: numberSize, weight: .light, design: .rounded)).minimumScaleFactor(0.55).lineLimit(1).monospacedDigit()
                    .contentTransition(.numericText())
                Text(title).watchText(.caption).foregroundStyle(.secondary)
            }
                .frame(minHeight: 30)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: value)
                .transaction { if reduceMotion { $0.disablesAnimations = true } }
                .focusable()
                .digitalCrownRotation($value, from: range.lowerBound, through: range.upperBound, by: step,
                                      sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: haptics)
                .accessibilityLabel(title)
                .accessibilityValue(WorkoutSession.number(value))
                .accessibilityHint("Use the Digital Crown or the increase and decrease buttons.")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: value = min(range.upperBound, value + step)
                    case .decrement: value = max(range.lowerBound, value - step)
                    @unknown default: break
                    }
                }
            HStack(spacing: 0) {
                Button { value = max(range.lowerBound, value - step) } label: {
                    Image(systemName: "minus").watchText(.body, weight: .light)
                }.accessibilityLabel("Decrease \(title)").disabled(value <= range.lowerBound)
                Button { value = min(range.upperBound, value + step) } label: {
                    Image(systemName: "plus").watchText(.body, weight: .light)
                }.accessibilityLabel("Increase \(title)").disabled(value >= range.upperBound)
            }
            .buttonStyle(QuietTextButtonStyle())
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .background(LiftStyle.surface, in: .rect(cornerRadius: 12))
    }
}

struct RestView: View {
    let store: WatchStore
    let session: WorkoutSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        WatchPage {
            VStack(spacing: 0) {
                if session.pendingEffort != nil {
                    Label("Rest", systemImage: "timer").watchText(.caption).foregroundStyle(.secondary)
                    RestClock(deadline: session.restUntil ?? Date(), duration: session.restDuration, compact: true)
                    EffortInvitation(store: store, session: session)
                } else {
                    RestPanel(deadline: session.restUntil ?? Date(), duration: session.restDuration,
                              exerciseName: session.currentExercise?.name, setNumber: session.currentSetNumber)
                }
            }
        } actions: {
            HStack(spacing: 8) {
                Button("+30 sec") { store.perform { try store.extendRest() } }
                Button("Skip") { store.perform { try store.skipRest() } }
            }.buttonStyle(QuietButtonStyle())
        }
        .task(id: session.restUntil) {
            guard let deadline = session.restUntil else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                try Task.checkCancellation()
                // Keep the notification intact when the app is in the background.
                guard scenePhase == .active else { return }
                store.perform { try store.restFinished(haptic: true) }
            } catch is CancellationError {} catch { store.error = error.localizedDescription }
        }
    }
}

struct RestPanel: View {
    let deadline: Date
    let duration: TimeInterval
    let exerciseName: String?
    let setNumber: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Rest", systemImage: "timer").watchText(.caption).foregroundStyle(.secondary)
            RestClock(deadline: deadline, duration: duration)
            if let exerciseName {
                Text("Next: \(exerciseName) · Set \(setNumber)")
                    .watchText(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Only this subtree refreshes each second. The two-point progress line has
/// explicit neutral colors rather than the system's tinted progress capsule.
struct RestClock: View {
    let deadline: Date
    let duration: TimeInterval
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var numberSize: CGFloat = 36

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
            let progress = min(1, max(0, 1 - deadline.timeIntervalSince(context.date) / max(1, duration)))
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                    .font(.system(size: compact ? numberSize * 0.65 : numberSize, weight: .light, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1).monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : LiftMotion.feedback, value: remaining)
                    .accessibilityLabel("Rest remaining").accessibilityValue("\(remaining) seconds")
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color(white: 0.18))
                        Rectangle().fill(Color(white: 0.8)).frame(width: geometry.size.width * progress)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: progress)
                    }
                }.frame(height: 2).accessibilityHidden(true)
            }
        }
    }
}

struct SummaryView: View {
    let store: WatchStore
    let session: WorkoutSession
    @ScaledMetric(relativeTo: .title3) private var metricSize: CGFloat = 20

    var body: some View {
        WatchPage {
            VStack(alignment: .leading, spacing: session.pendingEffort == nil ? 12 : 4) {
                HStack(spacing: 8) { LiftCompletionMark(); Text("Workout saved") }.watchText(.title)
                if session.pendingEffort != nil {
                    Text("\(session.entries.count) sets · \(Int(session.duration / 60)) min")
                        .watchText(.secondary).foregroundStyle(.secondary)
                    EffortInvitation(store: store, session: session)
                    Text("Done skips and sends.").watchText(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        summaryMetric("Sets", value: session.entries.count)
                        Spacer(minLength: 4)
                        summaryMetric("Min", value: Int(session.duration / 60))
                        Spacer(minLength: 4)
                        summaryMetric("Exercises", value: Set(session.entries.map(\.exerciseID)).count)
                    }
                    Text(store.summarySynced ? "Synced to iPhone" : "Saved on watch. Waiting for iPhone.")
                        .watchText(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            Button("Done") { store.perform { try store.dismissSummary() } }.buttonStyle(QuietButtonStyle(prominent: true))
        }
    }

    private func summaryMetric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number).font(.system(size: metricSize, weight: .light, design: .rounded)).monospacedDigit()
            Text(title).watchText(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

/// An invitation, not an automatic modal: ordinary Log/Rest/Done actions never
/// require an extra tap. Pending state is derived from the persisted session.
struct EffortInvitation: View {
    let store: WatchStore
    let session: WorkoutSession
    var body: some View {
        if session.pendingEffort != nil {
            Button("Rate last set · optional") { store.presentedSheet = .effort }
                .watchText(.caption)
                .buttonStyle(QuietTextButtonStyle())
        }
    }
}

struct EffortRatingView: View {
    let store: WatchStore
    let request: ObservationRequest
    let plan: WorkoutPlan
    @Environment(\.dismiss) private var dismiss
    @State private var rating = 5.0
    @State private var error: String?
    var body: some View {
        NavigationStack {
            WatchPage {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Effort · Set \(request.afterSet ?? 0)").watchText(.body)
                    Text(plan.exercises.first { $0.id == request.exerciseID }?.name ?? "Exercise")
                        .watchText(.caption).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 4) {
                        Button { rating = max(1, rating - 1) } label: { Image(systemName: "minus") }
                            .accessibilityLabel("Decrease effort").disabled(rating <= 1)
                        Text("\(Int(rating))/10").font(.title2.weight(.light)).monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .focusable()
                            .digitalCrownRotation($rating, from: 1, through: 10, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: store.state.haptics)
                            .accessibilityLabel("Effort").accessibilityValue("\(Int(rating)) out of 10")
                            .accessibilityAdjustableAction { direction in
                                if direction == .increment { rating = min(10, rating + 1) }
                                if direction == .decrement { rating = max(1, rating - 1) }
                            }
                        Button { rating = min(10, rating + 1) } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Increase effort").disabled(rating >= 10)
                    }.buttonStyle(QuietTextButtonStyle())
                    Text("1 easy · 10 maximal").watchText(.caption).foregroundStyle(.secondary)
                }
            } actions: {
                HStack(spacing: 8) {
                    Button("Skip") { save(nil) }
                    Button("Save") { save(Int(rating)) }
                }.buttonStyle(QuietButtonStyle())
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.buttonStyle(.plain) } }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func save(_ value: Int?) {
        do { try store.answerEffort(value); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct WatchOptionsView: View {
    let store: WatchStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingEnd = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let session = store.state.session, session.pendingEffort != nil {
                    Section("Coach observation") {
                        EffortInvitation(store: store, session: session)
                        Button("Skip effort rating") { perform { try store.answerEffort(nil) } }
                    }
                }
                if let session = store.state.session, session.phase != .completed {
                    Section("This workout") {
                        NavigationLink { AdaptiveWorkoutView(store: store) } label: { LiftLabel("Adjust workout", "arrow.triangle.branch") }
                        if !session.entries.isEmpty {
                            Button { perform(close: true) { try store.undo() } } label: { LiftLabel("Undo last set", "arrow.uturn.backward") }
                        }
                    }
                }
                if let plan = store.state.session?.plan ?? store.state.plan {
                    NavigationLink {
                        List {
                            ForEach(plan.exercises) { exercise in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(exercise.name)
                                    Text("\(exercise.sets) × \(exercise.reps) · \(WorkoutSession.number(exercise.weight)) \(plan.unit.rawValue)")
                                        .watchText(.secondary).foregroundStyle(.secondary)
                                    if let previous = store.previousResult(for: exercise, unit: plan.unit) {
                                        Text("Previous: \(previous)").watchText(.secondary).foregroundStyle(.secondary)
                                    }
                                }.accessibilityElement(children: .combine)
                            }
                        }.watchText(.body).navigationTitle("Details")
                    } label: { LiftLabel("Workout details", "list.bullet.rectangle") }
                }
                if let session = store.state.session, session.phase != .completed {
                    Section { Button { confirmingEnd = true } label: { LiftLabel("Finish early…", "stop.circle") } }
                }
                Section("Sync") {
                    if !store.syncNote.isEmpty { Text(store.syncNote).watchText(.caption).foregroundStyle(.secondary) }
                    Button(store.isSyncing ? "Syncing…" : "Sync with iPhone") { store.retrySync() }.disabled(store.isSyncing)
                    if !store.state.outbox.isEmpty {
                        Text("\(store.state.outbox.count) saved workout(s) waiting to sync").watchText(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    NavigationLink { WatchSettingsView(store: store) } label: { LiftLabel("Preferences", "slider.horizontal.3") }
                    if store.state.motionOptIn == true {
                        NavigationLink { MotionCaptureView(store: store) } label: { LiftLabel("Motion test", "waveform.path") }
                    }
                }
            }
            .watchText(.body)
            .navigationTitle("Options")
            .task { await store.refreshNotificationStatus() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.buttonStyle(.plain).foregroundStyle(.primary)
                }
            }
            .confirmationDialog("End this workout? Completed sets will be saved.", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("End and save") {
                    perform(close: true) { try store.finishEarly() }
                }
                Button("Keep training", role: .cancel) {}
            }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func perform(close: Bool = false, _ operation: () throws -> Void) {
        do {
            try operation()
            if close { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}

struct WatchSettingsView: View {
    let store: WatchStore
    var body: some View {
        List {
            Section("Feedback") {
                Toggle("Wrist haptics", isOn: Binding(get: { store.state.haptics }, set: { value in store.perform { try store.setHaptics(value) } }))
            }
            Section("Rest reminders") {
                Text(store.restReminderMessage).watchText(.caption).foregroundStyle(.secondary)
                if store.notificationStatus == .notDetermined {
                    Button("Allow reminders") { Task { await store.requestRestNotifications() } }
                }
            }
            Section {
                NavigationLink { ScrollView {
                    Text(store.connectionDetails).font(.caption2.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                }.navigationTitle("Connection") } label: { LiftLabel("Connection", "antenna.radiowaves.left.and.right") }
            }
        }.watchText(.body).navigationTitle("Preferences")
            .task { await store.refreshNotificationStatus() }
    }
}

// Layout previews use the real panels without starting stores or connectivity.
#Preview("Log set") {
    NavigationStack {
        WatchPage {
            WorkoutSetPanel(exercise: ExercisePlan(name: "Bench press", sets: 3, reps: 10, weight: 40),
                            unit: .kg, setNumber: 1, weight: .constant(40), reps: .constant(10), haptics: false)
        } actions: { Button("Log set") {}.buttonStyle(QuietButtonStyle()) }
    }.tint(LiftStyle.accent).preferredColorScheme(.dark)
}

#Preview("Rest") {
    NavigationStack {
        WatchPage {
            RestPanel(deadline: .now.addingTimeInterval(76), duration: 90, exerciseName: "Bench press", setNumber: 2)
        } actions: {
            HStack(spacing: 8) { Button("+30 sec") {}; Button("Skip") {} }.buttonStyle(QuietButtonStyle())
        }
    }.tint(LiftStyle.accent).preferredColorScheme(.dark)
}
