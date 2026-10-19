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
    @State private var keptPlan: WorkoutPlan?

    var body: some View {
        NavigationStack {
            Group {
                if store.state.canReplaceUnloggedWorkout, keptPlan != store.state.plan, let plan = store.state.plan {
                    WatchPage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.s("New workout")).watchText(.caption).foregroundStyle(.secondary)
                            Text(plan.title).watchText(.title).lineLimit(2)
                            Text(L10n.s("No sets logged yet.")).watchText(.secondary)
                        }
                    } actions: {
                        Button(L10n.s("Use new workout")) { store.perform { try store.replaceUnloggedWorkout() } }.buttonStyle(QuietButtonStyle(prominent: true))
                        Button(L10n.s("Keep current workout")) { keptPlan = plan }.buttonStyle(QuietTextButtonStyle())
                    }
                } else if let session = store.state.session {
                    switch session.phase {
                    case .active:
                        if let exercise = session.currentExercise, exercise.kind != .strength { TimedActivityView(store: store, session: session, exercise: exercise) }
                        else { SetView(store: store, session: session) }
                    case .transitioning: TransitionView(store: store, session: session)
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
                    .accessibilityLabel(L10n.s("Workout options"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let session = store.state.session, session.phase != .completed {
                        Button { store.presentedSheet = .adjust } label: { Image(systemName: "arrow.triangle.branch") }.buttonStyle(.plain).accessibilityLabel(L10n.s("Change exercise"))
                    }
                }
            }
            .sheet(item: $store.presentedSheet) { sheet in
                switch sheet {
                case .options: WatchOptionsView(store: store)
                case .adjust: NavigationStack { AdaptiveWorkoutView(store: store).toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.s("Done")) { store.presentedSheet = nil } } } }
                case .motion:
                    NavigationStack {
                        MotionCaptureView(store: store)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.s("Done")) { store.presentedSheet = nil } } }
                    }
                case .effort:
                    if let session = store.state.session, let request = session.pendingEffort {
                        EffortRatingView(store: store, request: request, plan: session.plan)
                    }
                }
            }
            .alert(L10n.s("Couldn’t save"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button(L10n.s("OK")) { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
        .onChange(of: scenePhase) { _, phase in RhythmGuide.shared.sceneChanged(active: phase == .active); WorkoutRuntime.shared.scene(String(describing: phase)); if phase == .active { store.foreground() } }
        .onAppear { RhythmGuide.shared.sceneChanged(active: scenePhase == .active); store.foreground() }
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
                    Text(plan.title).font(.system(size: titleSize, weight: .regular, design: .default)).lineLimit(2)
                    Text(LiftCopy.workoutSummary(plan))
                        .watchText(.secondary).foregroundStyle(.secondary)
                    if let first = plan.exercises.first {
                        Divider().padding(.vertical, 2)
                        Text(L10n.s("First · \(first.name)")).watchText(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                } else {
                    Text(L10n.s("No workout yet")).watchText(.title)
                    Text(L10n.s("Open Little Lift on your paired iPhone and import a plan."))
                        .watchText(.secondary).foregroundStyle(.secondary)
                    if !store.syncNote.isEmpty {
                        Text(store.syncNote).watchText(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            if store.state.plan != nil {
                Button { store.perform { try store.start() } } label: { Label(L10n.s("Start workout"), systemImage: "play.fill") }
                    .buttonStyle(QuietButtonStyle(prominent: true))
            } else {
                Button(store.isSyncing ? L10n.s("Syncing…") : L10n.s("Sync with iPhone")) { store.retrySync() }
                    .buttonStyle(QuietButtonStyle()).disabled(store.isSyncing)
            }
        }
    }
}

struct SetView: View {
    @State private var confirmingZero = false
    @Bindable var store: WatchStore
    let session: WorkoutSession

    var body: some View {
        WatchPage {
            VStack(spacing: 0) {
                EffortInvitation(store: store, session: session)
                if let exercise = session.currentExercise {
                    WorkoutSetPanel(exercise: exercise, unit: session.plan.unit, setNumber: session.currentSetNumber,
                                weight: $store.draftWeight, reps: $store.draftReps, haptics: store.state.haptics, completedExercises: session.completedExerciseCount, totalExercises: session.plan.exercises.count)
                }
            }
        } actions: {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let allowed = LogActionGuard.allows(session: session, presentedSheet: store.presentedSheet != nil, now: context.date)
                Button { if store.needsLoadChoice { confirmingZero = true } else { store.perform { try store.logSet() } } } label: { Label(store.needsLoadChoice ? L10n.s("Choose load") : RhythmGuide.shared.active ? L10n.s("Done · log set") : L10n.s("Log set"), systemImage: "checkmark") }.buttonStyle(QuietButtonStyle(prominent: true))
                    .disabled(!allowed)
                    .handGestureShortcut(.primaryAction, isEnabled: allowed && !store.needsLoadChoice && store.state.doubleTapEnabled == true)
            }
        }
        .confirmationDialog(L10n.s("Choose the actual load"), isPresented: $confirmingZero, titleVisibility: .visible) {
            Button(L10n.s("Log without load · 0 kg/lb")) { store.perform { try store.logSet(confirmZeroLoad: true) } }
            Button(L10n.s("Adjust weight with + or Crown"), role: .cancel) { }
        }
        .id(session.currentExercise?.id)
        .onDisappear { RhythmGuide.shared.stop() }
    }
}

struct WorkoutSetPanel: View {
    let exercise: ExercisePlan
    let unit: WeightUnit
    let setNumber: Int
    @Binding var weight: Double
    @Binding var reps: Double
    let haptics: Bool
    var completedExercises = 0
    var totalExercises = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 0) {
                Text(exercise.name).watchText(.body).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(L10n.s("Set \(setNumber) of \(exercise.sets)")).watchText(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if totalExercises > 0 {
                        Text(L10n.s("\(completedExercises)/\(totalExercises) ex."))
                            .watchText(.caption).foregroundStyle(.secondary).monospacedDigit()
                            .accessibilityLabel(L10n.s("\(completedExercises) of \(totalExercises) exercises completed"))
                    }
                }
            }
            HStack(spacing: 6) {
                WatchNumberField(title: unit.rawValue.uppercased(), value: $weight,
                                 step: unit == .kg ? 0.5 : 1, range: 0...1000, haptics: haptics)
                WatchNumberField(title: L10n.s("REPS"), value: $reps, step: 1, range: 1...200, haptics: haptics)
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
                .accessibilityHint(L10n.s("Use the Digital Crown or the increase and decrease buttons."))
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
                }.accessibilityLabel(L10n.s("Decrease \(title)")).disabled(value <= range.lowerBound)
                Button { value = min(range.upperBound, value + step) } label: {
                    Image(systemName: "plus").watchText(.body, weight: .light)
                }.accessibilityLabel(L10n.s("Increase \(title)")).disabled(value >= range.upperBound)
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
                WorkoutProgressLine(session: session)
                WaterReminderView(store: store)
                if session.pendingEffort != nil {
                    Label(L10n.s("Rest"), systemImage: "timer").watchText(.caption).foregroundStyle(.secondary)
                    RestClock(deadline: session.restUntil ?? Date(), duration: session.restDuration, compact: true)
                    EffortInvitation(store: store, session: session)
                } else {
                    RestPanel(deadline: session.restUntil ?? Date(), duration: session.restDuration,
                              exerciseName: session.currentExercise?.name, setNumber: session.currentSetNumber)
                }
            }
        } actions: {
            HStack(spacing: 8) {
                Button(L10n.s("+30 sec")) { store.perform { try store.extendRest() } }
                Button(L10n.s("Skip")) { store.perform { try store.skipRest() } }
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
            Label(L10n.s("Rest"), systemImage: "timer").watchText(.caption).foregroundStyle(.secondary)
            RestClock(deadline: deadline, duration: duration)
            if let exerciseName {
                Text(L10n.s("Next: \(exerciseName) · Set \(setNumber)"))
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
    @ScaledMetric(relativeTo: .title2) private var numberSize: CGFloat = 32

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
            let progress = min(1, max(0, 1 - deadline.timeIntervalSince(context.date) / max(1, duration)))
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                    .font(.system(size: compact ? numberSize * 0.65 : numberSize, weight: .light, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1).monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : LiftMotion.feedback, value: remaining)
                    .accessibilityLabel(L10n.s("Rest remaining")).accessibilityValue(L10n.s("\(remaining) seconds"))
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
                HStack(spacing: 8) { LiftCompletionMark(animate: store.state.comfort?.quietFeedback != true); Text(L10n.s("Workout saved")) }.watchText(.title)
                if session.pendingEffort != nil {
                    Text(L10n.s("\(session.loggedWorkCount) sets / segments · \(Int(session.duration / 60)) min"))
                        .watchText(.secondary).foregroundStyle(.secondary)
                    EffortInvitation(store: store, session: session)
                    Text(L10n.s("Done skips and sends.")).watchText(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        summaryMetric(L10n.s("Logged"), value: session.loggedWorkCount)
                        Spacer(minLength: 4)
                        summaryMetric(L10n.s("Min"), value: Int(session.duration / 60))
                        Spacer(minLength: 4)
                        summaryMetric(L10n.s("Exercises"), value: Set((session.entries.map(\.exerciseID) + (session.activities ?? []).map(\.exerciseID)).map { session.originalID(for: $0) }).count)
                    }
                    if let feedback = session.feedback, store.state.comfort?.quietFeedback != true { Text(feedback).watchText(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    Text(store.summarySynced ? L10n.s("Synced to iPhone") : L10n.s("Saved on watch. Waiting for iPhone."))
                        .watchText(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            Button(L10n.s("Done")) { store.perform { try store.dismissSummary() } }.buttonStyle(QuietButtonStyle(prominent: true))
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
            Button(L10n.s("Rate last set · optional")) { store.presentedSheet = .effort }
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
                    Text(L10n.s("Effort · Set \(request.afterSet ?? 0)")).watchText(.body)
                    Text(plan.exercises.first { $0.id == request.exerciseID }?.name ?? L10n.s("Exercise"))
                        .watchText(.caption).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 4) {
                        Button { rating = max(1, rating - 1) } label: { Image(systemName: "minus") }
                            .accessibilityLabel(L10n.s("Decrease effort")).disabled(rating <= 1)
                        Text(L10n.s("\(Int(rating))/10")).font(.title2.weight(.light)).monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .focusable()
                            .digitalCrownRotation($rating, from: 1, through: 10, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: store.state.haptics)
                            .accessibilityLabel(L10n.s("Effort")).accessibilityValue(L10n.s("\(Int(rating)) out of 10"))
                            .accessibilityAdjustableAction { direction in
                                if direction == .increment { rating = min(10, rating + 1) }
                                if direction == .decrement { rating = max(1, rating - 1) }
                            }
                        Button { rating = min(10, rating + 1) } label: { Image(systemName: "plus") }
                            .accessibilityLabel(L10n.s("Increase effort")).disabled(rating >= 10)
                    }.buttonStyle(QuietTextButtonStyle())
                    Text(L10n.s("1 easy · 10 maximal")).watchText(.caption).foregroundStyle(.secondary)
                }
            } actions: {
                HStack(spacing: 8) {
                    Button(L10n.s("Skip")) { save(nil) }
                    Button(L10n.s("Save")) { save(Int(rating)) }
                }.buttonStyle(QuietButtonStyle())
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.s("Close")) { dismiss() }.buttonStyle(.plain) } }
            .alert(L10n.s("Couldn’t save"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(L10n.s("OK")) { error = nil }
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
                if let session = store.state.session, session.phase == .active, session.currentExercise?.kind == .strength,
                   store.state.comfort?.rhythmEnabled == true, store.state.haptics {
                    Section(L10n.s("Rhythm guide")) {
                        Button(RhythmGuide.shared.active ? L10n.s("Stop rhythm guide") : L10n.s("Start rhythm guide")) {
                            let stop = RhythmGuide.shared.active
                            dismiss()
                            if stop { RhythmGuide.shared.stop() } else { RhythmGuide.shared.start(store: store) }
                        }
                    }
                }
                if let session = store.state.session, session.pendingEffort != nil {
                    Section(L10n.s("Coach observation")) {
                        EffortInvitation(store: store, session: session)
                        Button(L10n.s("Skip effort rating")) { perform { try store.answerEffort(nil) } }
                    }
                }
                if let session = store.state.session, session.phase != .completed {
                    Section(L10n.s("This workout")) {
                        NavigationLink { AdaptiveWorkoutView(store: store) } label: { LiftLabel(L10n.s("Adjust workout"), "arrow.triangle.branch") }
                        if session.hasRecordedWork {
                            Button { perform(close: true) { try store.undo() } } label: { LiftLabel(L10n.s("Undo last set"), "arrow.uturn.backward") }
                        }
                    }
                }
                if let plan = store.state.session?.plan ?? store.state.plan {
                    NavigationLink {
                        List {
                            ForEach(plan.exercises) { exercise in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(exercise.name)
                                    Text(exercise.prescription(unit: plan.unit))
                                        .watchText(.secondary).foregroundStyle(.secondary)
                                    if let previous = store.previousResult(for: exercise, unit: plan.unit) {
                                        Text(L10n.s("Previous: \(previous)")).watchText(.secondary).foregroundStyle(.secondary)
                                    }
                                }.accessibilityElement(children: .combine)
                            }
                        }.watchText(.body).navigationTitle(L10n.s("Details"))
                    } label: { LiftLabel(L10n.s("Workout details"), "list.bullet.rectangle") }
                }
                if let session = store.state.session, session.phase != .completed {
                    Section { Button { confirmingEnd = true } label: { LiftLabel(L10n.s("Finish early…"), "stop.circle") } }
                }
                Section(L10n.s("Sync")) {
                    if !store.syncNote.isEmpty { Text(store.syncNote).watchText(.caption).foregroundStyle(.secondary) }
                    Button(store.isSyncing ? L10n.s("Syncing…") : L10n.s("Sync with iPhone")) { store.retrySync() }.disabled(store.isSyncing)
                    if !store.state.outbox.isEmpty {
                        Text(L10n.s("\(store.state.outbox.count) saved workout(s) waiting to sync")).watchText(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    NavigationLink { WatchSettingsView(store: store) } label: { LiftLabel(L10n.s("Preferences"), "slider.horizontal.3") }
                    if store.state.motionOptIn == true {
                        NavigationLink { MotionCaptureView(store: store) } label: { LiftLabel(L10n.s("Motion test"), "waveform.path") }
                    }
                }
            }
            .watchText(.body)
            .navigationTitle(L10n.s("Options"))
            .task { await store.refreshNotificationStatus() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.s("Done")) { dismiss() }.buttonStyle(.plain).foregroundStyle(.primary)
                }
            }
            .confirmationDialog(L10n.s("End this workout? Completed sets will be saved."), isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button(L10n.s("End and save")) {
                    perform(close: true) { try store.finishEarly() }
                }
                Button(L10n.s("Keep training"), role: .cancel) {}
            }
            .alert(L10n.s("Couldn’t save"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(L10n.s("OK")) { error = nil }
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
            Section(L10n.s("Feedback")) {
                Toggle(L10n.s("Wrist haptics"), isOn: Binding(get: { store.state.haptics }, set: { value in store.perform { try store.setHaptics(value) } }))
            }
            Section(L10n.s("Workout runtime")) {
                Text(WorkoutRuntime.shared.status).watchText(.caption)
                if let session = store.state.session, session.phase != .completed, !WorkoutRuntime.shared.running {
                    Button(L10n.s("Enable workout runtime")) { Task { await WorkoutRuntime.shared.start(for: session) } }.disabled(WorkoutRuntime.shared.starting)
                }
            }
            Section(L10n.s("Rest reminders")) {
                Text(store.restReminderMessage).watchText(.caption).foregroundStyle(.secondary)
                if store.notificationStatus == .notDetermined {
                    Button(L10n.s("Allow reminders")) { Task { await store.requestRestNotifications() } }
                }
            }
            Section {
                NavigationLink { ScrollView {
                    Text(store.connectionDetails).font(.caption2.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                }.navigationTitle(L10n.s("Connection")) } label: { LiftLabel(L10n.s("Connection"), "antenna.radiowaves.left.and.right") }
            }
        }.watchText(.body).navigationTitle(L10n.s("Preferences"))
            .task { await store.refreshNotificationStatus() }
    }
}

// Layout previews use the real panels without starting stores or connectivity.
#Preview("Log set") {
    NavigationStack {
        WatchPage {
            WorkoutSetPanel(exercise: ExercisePlan(name: "Bench press", sets: 3, reps: 10, weight: 40),
                            unit: .kg, setNumber: 1, weight: .constant(40), reps: .constant(10), haptics: false)
        } actions: { Button(L10n.s("Log set")) {}.buttonStyle(QuietButtonStyle()) }
    }.tint(LiftStyle.accent).preferredColorScheme(.dark)
}

#Preview("Rest") {
    NavigationStack {
        WatchPage {
            RestPanel(deadline: .now.addingTimeInterval(76), duration: 90, exerciseName: "Bench press", setNumber: 2)
        } actions: {
            HStack(spacing: 8) { Button(L10n.s("+30 sec")) {}; Button(L10n.s("Skip")) {} }.buttonStyle(QuietButtonStyle())
        }
    }.tint(LiftStyle.accent).preferredColorScheme(.dark)
}
