import SwiftUI
import WatchKit
import Observation

/// Optional metronome. Pulses are never repetitions or sensor evidence.
@MainActor @Observable final class RhythmGuide {
    static let shared = RhythmGuide()
    private(set) var active = false
    private(set) var pulses = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var token: UUID?
    @ObservationIgnored private var appActive = true
    func sceneChanged(active: Bool) {
        appActive = active
        if !active && !WorkoutRuntime.shared.running { stop() }
    }
    func start(store: WatchStore) {
        stop()
        guard store.state.haptics, store.state.comfort?.rhythmEnabled == true,
              let session = store.state.session, session.phase == .active, let exercise = session.currentExercise, exercise.kind == .strength else { return }
        let current = UUID(); token = current; active = true; pulses = 0
        let interval = store.state.comfort?.rhythmSeconds ?? 3
        task = Task { @MainActor [weak self, weak store] in
            for _ in 0..<120 {
                do { try await Task.sleep(for: .seconds(interval)); try Task.checkCancellation() } catch { return }
                guard let self, let store, self.token == current,
                      RhythmEligibility.allows(appActive: self.appActive, workoutRunning: WorkoutRuntime.shared.running,
                        haptics: store.state.haptics, enabled: store.state.comfort?.rhythmEnabled == true,
                        sameSet: store.state.session?.id == session.id && store.state.session?.phase == .active &&
                            store.state.session?.entries.count == session.entries.count && store.state.session?.currentExercise?.id == exercise.id)
                else { self?.stop(); return }
                WKInterfaceDevice.current().play(.click); self.pulses += 1
            }
            self?.stop()
        }
    }
    func stop() { task?.cancel(); task = nil; token = nil; active = false; pulses = 0 }
}
struct WaterReminderView: View {
    let store: WatchStore
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let due = store.state.session?.hydrationDue, context.date >= due {
                HStack(spacing: 4) {
                    Text(L10n.s("Water")).watchText(.caption).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    Button(L10n.s("Later")) { store.perform { try store.waterReminder(snooze: true) } }.accessibilityLabel(L10n.s("Snooze water reminder"))
                    Button { store.perform { try store.waterReminder(snooze: false) } } label: { Image(systemName: "xmark") }.frame(width: 44).accessibilityLabel(L10n.s("Turn off for this workout"))
                }.watchText(.caption).buttonStyle(QuietTextButtonStyle())
            }
        }
    }
}
