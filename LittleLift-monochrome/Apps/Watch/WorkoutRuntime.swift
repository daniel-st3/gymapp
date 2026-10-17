import Foundation
import HealthKit
import Observation
import WatchKit
import os

/// One real HealthKit session for the workout. It does not collect Health history,
/// fabricate energy/distance, or use extended-runtime categories as a keepalive.
@MainActor @Observable final class WorkoutRuntime: NSObject, HKWorkoutSessionDelegate {
    static let shared = WorkoutRuntime()
    private(set) var status = L10n.s("Manual logging ready")
    private(set) var running = false
    private(set) var starting = false
    @ObservationIgnored private let health = HKHealthStore()
    @ObservationIgnored private var workout: HKWorkoutSession?
    @ObservationIgnored private var attempt: UUID?
    @ObservationIgnored private var recoveryInProgress = false
    @ObservationIgnored private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LittleLift", category: "WorkoutLifecycle")
    private let ownerKey = "littlelift.runtime.session"

    func start(for session: WorkoutSession) async {
        for _ in 0..<100 where recoveryInProgress {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
        guard !recoveryInProgress else { status = L10n.s("Workout runtime recovery is still pending. Manual logging is ready."); return }
        guard workout == nil, !starting, session.phase != .completed,
              WatchStore.shared.state.session?.id == session.id, WatchStore.shared.state.session?.phase != .completed else { return }
        guard !MotionCapture.shared.active, !MotionCapture.shared.starting else {
            status = L10n.s("Stop the motion test first. Manual logging still works."); return
        }
        let token = UUID(); attempt = token; starting = true
        defer { if attempt == token { starting = false; attempt = nil } }
        do {
            guard HKHealthStore.isHealthDataAvailable() else { throw WorkoutError.invalidState(L10n.s("Health is unavailable. Manual logging still works.")) }
            status = L10n.s("Allow Workouts to support wrist-down training.")
            try await health.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            guard attempt == token, WatchStore.shared.state.session?.id == session.id,
                  WatchStore.shared.state.session?.phase != .completed else { return }
            guard health.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
                status = L10n.s("Manual logging. To enable workout runtime: Watch Settings → Health → Apps → Little Lift → Workouts.")
                record("permission denied"); return
            }
            let config = HKWorkoutConfiguration()
            config.activityType = activityType(for: session.currentExercise?.kind); config.locationType = .indoor
            let new = try HKWorkoutSession(healthStore: health, configuration: config)
            new.delegate = self; workout = new
            UserDefaults.standard.set(session.id.uuidString, forKey: ownerKey)
            new.startActivity(with: Date())
            status = L10n.s("Starting workout runtime…"); record("start requested")
        } catch {
            status = L10n.s("Manual logging. Workout runtime unavailable: \(error.localizedDescription)")
            record("start failed: \((error as NSError).code)")
        }
    }

    /// Recovery attaches only to this app's existing session; it never starts a
    /// replacement in response to a foreground event or another app's workout.
    func recover() async {
        guard workout == nil, !starting, !recoveryInProgress, !MotionCapture.shared.active, !MotionCapture.shared.starting else { return }
        recoveryInProgress = true
        defer { recoveryInProgress = false }
        do {
            guard let recovered = try await health.recoverActiveWorkoutSession() else { return }
            guard let local = WatchStore.shared.state.session, local.phase != .completed,
                  UserDefaults.standard.string(forKey: ownerKey) == local.id.uuidString else {
                recovered.end(); record("orphaned app runtime ended; local log preserved"); return
            }
            workout = recovered; recovered.delegate = self
            running = recovered.state == .running
            status = running ? L10n.s("Workout runtime recovered") : L10n.s("Workout paused by watchOS. Your log is safe.")
            record("runtime recovered")
        } catch { record("recovery unavailable: \((error as NSError).code)") }
    }
    private func activityType(for kind: ActivityKind?) -> HKWorkoutActivityType {
        switch kind { case .walking: .walking; case .running: .running; case .mobility: .flexibility; case .other: .other; default: .traditionalStrengthTraining }
    }
    func changeActivity(_ exercise: ExercisePlan?) {
        guard running, let workout, let exercise else { return }
        let configuration = HKWorkoutConfiguration(); configuration.locationType = .indoor
        configuration.activityType = activityType(for: exercise.kind)
        workout.beginNewActivity(configuration: configuration, date: Date(), metadata: nil)
        record("activity changed")
    }
    func finish() {
        RhythmGuide.shared.stop()
        attempt = nil; starting = false
        let old = workout; workout = nil; running = false
        old?.end(); UserDefaults.standard.removeObject(forKey: ownerKey)
        status = L10n.s("Workout ended. Log saved in Little Lift."); record("finished")
    }
    func scene(_ phase: String) { record("scene \(phase)") }
    private func record(_ event: String) {
        log.info("\(event, privacy: .public)")
        // Bounded local diagnostics contain no exercises, Health samples or personal history.
        var events = UserDefaults.standard.stringArray(forKey: "littlelift.runtime.events") ?? []
        events.append("\(ISO8601DateFormatter().string(from: Date())) \(event)")
        UserDefaults.standard.set(Array(events.suffix(40)), forKey: "littlelift.runtime.events")
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor [weak self] in
            guard let self, self.workout === workoutSession else { return }
            self.running = toState == .running
            if !self.running { RhythmGuide.shared.stop() }
            self.record("state \(fromState.rawValue) → \(toState.rawValue)")
            if toState == .ended || toState == .stopped {
                self.workout = nil
                self.status = L10n.s("Workout runtime stopped. Your sets are saved; continue manually or enable runtime in Preferences.")
            } else { self.status = self.running ? L10n.s("Workout runtime active") : L10n.s("Workout paused by watchOS. Your log is safe.") }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.workout === workoutSession else { return }
            RhythmGuide.shared.stop()
            self.workout = nil; self.running = false
            self.status = L10n.s("Workout runtime interrupted. Manual logging still works.")
            self.record("interrupted: \((error as NSError).code)")
        }
    }
}

final class WorkoutApplicationDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() { Task { @MainActor in await WorkoutRuntime.shared.recover() } }
}
