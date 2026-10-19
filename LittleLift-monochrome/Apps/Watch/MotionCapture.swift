import Foundation
import Observation
import CoreMotion
import HealthKit
import WatchKit
import SwiftUI

@MainActor @Observable final class MotionCapture: NSObject, HKWorkoutSessionDelegate {
    static let shared = MotionCapture()
    private(set) var active = false
    private(set) var starting = false
    private(set) var sampleCount = 0
    private(set) var message = L10n.s("Ready for a short test.")
    private(set) var elapsed = 0.0
    private(set) var recordingExercise = ""
    private(set) var queuedRecordID: UUID?
    var error: String?
    private(set) var latest: MotionRecording?
    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private let health = HKHealthStore()
    @ObservationIgnored private var workout: HKWorkoutSession?
    @ObservationIgnored private var current: MotionRecording?
    @ObservationIgnored private var origin: TimeInterval?
    @ObservationIgnored private var startAttempt: UUID?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var sensorTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    let repository = MotionRepository(folder: URL.applicationSupportDirectory.appending(path: "LittleLiftMotion", directoryHint: .isDirectory))
    private override init() {
        super.init()
        do {
            for var record in try repository.recordings() where record.status == "recording" {
                record.status = "interrupted"; try repository.save(record)
                message = L10n.s("Interrupted samples preserved. Check the Watch workout indicator before starting another experiment.")
            }
            latest = try repository.recordings().first
        } catch { message = L10n.s("Motion data preserved but unreadable: \(error.localizedDescription)") }
    }
    func start(exercise: String) async {
        guard !active, !starting else { return }
        guard WatchStore.shared.state.session == nil || WatchStore.shared.state.session?.phase == .completed else {
            error = L10n.s("Finish your workout before starting a motion test."); return
        }
        let attempt = UUID(); startAttempt = attempt
        starting = true; error = nil; message = L10n.s("Waiting for Apple permission. Check this Watch and your iPhone.")
        defer {
            if startAttempt == attempt { starting = false; startAttempt = nil; permissionTask?.cancel() }
        }
        await Task.yield()
        do {
            guard manager.isDeviceMotionAvailable, HKHealthStore.isHealthDataAvailable() else { throw WorkoutError.invalidState(L10n.s("Motion capture requires a physical Apple Watch with motion and HealthKit available.")) }
            guard try repository.recordings().count < 20 else { throw WorkoutError.invalidState(L10n.s("20 local experimental recordings saved. Delete/export on Watch before starting another.")) }
            permissionTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                guard let self, self.startAttempt == attempt else { return }
                self.message = L10n.s("Still waiting for permission. You can cancel and try again.")
            }
            try await health.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            guard startAttempt == attempt else { return }
            permissionTask?.cancel()
            switch health.authorizationStatus(for: HKObjectType.workoutType()) {
            case .sharingAuthorized: break
            case .sharingDenied:
                throw WorkoutError.invalidState(L10n.s("Allow Workouts in Watch Settings → Health → Apps → Little Lift, then retry."))
            case .notDetermined:
                throw WorkoutError.invalidState(L10n.s("Apple hasn’t completed permission setup. Check Watch Settings → Health → Apps → Little Lift, then retry."))
            @unknown default:
                throw WorkoutError.invalidState(L10n.s("Workouts permission is unavailable. Check Watch Settings → Health → Apps → Little Lift."))
            }
            guard WatchStore.shared.state.motionOptIn == true else { throw WorkoutError.invalidState(L10n.s("Motion opt-in is off on iPhone.")) }
            let config = HKWorkoutConfiguration(); config.activityType = .traditionalStrengthTraining; config.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: health, configuration: config)
            session.delegate = self; workout = session
            recordingExercise = exercise
            var record = MotionRecording(exercise: exercise)
            WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
            let battery = WKInterfaceDevice.current().batteryLevel
            record.batteryStart = battery >= 0 ? Double(battery) : nil
            try repository.save(record); current = record; latest = nil; queuedRecordID = nil
            origin = nil; sampleCount = 0; elapsed = 0; active = true
            let captureID = record.id
            session.startActivity(with: Date())
            manager.deviceMotionUpdateInterval = 1.0 / 25.0
            manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                Task { @MainActor in
                    guard let self, self.active, self.current?.id == captureID else { return }
                    if let error { self.fail(error.localizedDescription); return }
                    guard let motion else { return }
                    self.add(timestamp: motion.timestamp, x: motion.rotationRate.x, y: motion.rotationRate.y, z: motion.rotationRate.z)
                }
            }
            message = L10n.s("Waiting for sensor data…")
            sensorTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard let self, self.active, self.current?.id == captureID, self.current?.samples.isEmpty == true else { return }
                self.fail(L10n.s("No motion samples arrived. Check Watch Settings → Privacy & Security → Motion & Fitness, then try again."))
            }
            stopTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(180)) } catch { return }
                guard let self, self.current?.id == captureID else { return }
                self.stop(status: "time limit")
            }
        } catch {
            guard startAttempt == attempt else { return }
            active = false; self.error = error.localizedDescription; message = L10n.s("Couldn’t start.")
            workout?.end(); workout = nil
        }
    }
    func cancelStart() {
        startAttempt = nil; starting = false; permissionTask?.cancel()
        message = L10n.s("Cancelled. No recording started.")
    }
    private func fail(_ detail: String) {
        stop(status: "interrupted"); error = detail; message = L10n.s("Capture stopped.")
    }
    func sendLatest() throws {
        guard !active, let latest, !latest.samples.isEmpty else { return }
        try WatchStore.shared.sendMotion(repository.url(latest.id), id: latest.id)
        queuedRecordID = latest.id; message = L10n.s("Queued for iPhone.")
    }
    func deleteLatest() throws { if let latest { try repository.delete(latest.id) }; latest = try repository.recordings().first }
    private func add(timestamp: Double, x: Double, y: Double, z: Double) {
        guard var record = current else { return }
        if origin == nil { origin = timestamp }
        let t = timestamp - (origin ?? timestamp)
        guard t <= 180, record.samples.count < 4500 else { stop(status: "time limit"); return }
        guard record.samples.last.map({ t > $0.t }) ?? true else { return }
        if record.samples.isEmpty, WatchStore.shared.state.haptics { WKInterfaceDevice.current().play(.start) }
        record.samples.append(MotionSample(t: t, x: x, y: y, z: z)); current = record
        if record.samples.count % 50 == 0 {
            sampleCount = record.samples.count; elapsed = t; message = L10n.s("Recording · stops at 3 min")
            do { try repository.save(record) } catch { fail(error.localizedDescription) }
        }
    }
    func stop(status: String = "stopped") {
        guard active else { return }; active = false; stopTask?.cancel(); stopTask = nil; sensorTask?.cancel()
        manager.stopDeviceMotionUpdates(); workout?.end(); workout = nil
        guard var record = current else { return }
        record.status = status
        let battery = WKInterfaceDevice.current().batteryLevel; record.batteryEnd = battery >= 0 ? Double(battery) : nil
        do { try repository.save(record); latest = record; sampleCount = record.samples.count; elapsed = record.duration; message = record.samples.isEmpty ? L10n.s("No movement data was captured.") : L10n.s("Saved on Watch.") }
        catch {
            // A prior replay must not be sent or presented as this capture.
            // The last durable checkpoint remains recoverable after relaunch.
            message = L10n.s("Could not save the last samples. Reopen Little Lift to recover the saved checkpoint.")
            self.error = L10n.s("\(message) \(error.localizedDescription)")
            current = nil
            return
        }
        current = nil
        if !record.samples.isEmpty {
            if WatchStore.shared.state.haptics { WKInterfaceDevice.current().play(.stop) }
            do { try sendLatest() } catch { message = L10n.s("Saved on Watch. Tap Send to retry.") }
        }
        // No HKWorkoutBuilder is collected or finished, and no HKWorkout is saved.
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended || toState == .stopped || toState == .paused { Task { @MainActor [weak self] in
            guard let self, self.workout === workoutSession else { return }
            self.stop(status: "interrupted")
        } }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.workout === workoutSession else { return }
            self.fail(error.localizedDescription)
        }
    }
}

struct MotionCaptureView: View {
    let store: WatchStore
    @State private var capture = MotionCapture.shared
    @State private var readyForNew = false
    @State private var queued = false
    @State private var deleting = false
    private var saved: MotionRecording? { readyForNew ? nil : capture.latest }
    private var sent: Bool { queued || (saved != nil && capture.queuedRecordID == saved?.id) }
    var body: some View {
        WatchPage {
            VStack(alignment: .leading, spacing: 10) {
                if capture.active || capture.starting || saved != nil {
                    Text(capture.active ? L10n.s("Recording") : capture.starting ? L10n.s("Allow access") : L10n.s("Replay saved"))
                        .watchText(.title)
                }
                Text((capture.active ? capture.recordingExercise : saved?.exercise ?? store.state.motionExercise?.rawValue) ?? L10n.s("Dumbbell curl"))
                    .watchText(.body).fixedSize(horizontal: false, vertical: true)
                if capture.active {
                    Text(L10n.s("\(Int(capture.elapsed)) seconds")).font(.title3.weight(.light)).monospacedDigit()
                    Text(capture.message).watchText(.secondary).foregroundStyle(.secondary)
                } else if capture.starting {
                    Text(capture.message).watchText(.secondary).foregroundStyle(.secondary)
                } else if let record = saved {
                    Text(sent ? L10n.s("Queued. Open Motion test on iPhone.") : L10n.s("\(Int(record.duration)) seconds · \(record.samples.count) samples"))
                        .watchText(.secondary).foregroundStyle(.secondary)
                    Button(L10n.s("Delete replay")) { deleting = true }.watchText(.secondary)
                } else {
                    Text(store.state.motionOptIn == true ? L10n.s("3-minute test.\nStop other workout apps first.") : L10n.s("Enable Motion test in iPhone Settings first."))
                        .watchText(.secondary).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            if capture.active {
                Button(L10n.s("Stop")) { capture.stop(); readyForNew = false }.buttonStyle(QuietButtonStyle())
            } else if capture.starting {
                Button(L10n.s("Cancel")) { capture.cancelStart() }.buttonStyle(QuietButtonStyle())
            } else if let record = saved {
                VStack(spacing: 6) {
                    Button(sent ? L10n.s("Queued for iPhone") : L10n.s("Send to iPhone")) {
                        do { try capture.sendLatest(); queued = true }
                        catch { capture.error = error.localizedDescription }
                    }.buttonStyle(QuietButtonStyle()).disabled(sent || record.samples.isEmpty)
                    Button(L10n.s("New test")) { readyForNew = true; queued = false }.buttonStyle(QuietTextButtonStyle())
                }
            } else {
                Button(L10n.s("Start")) {
                    readyForNew = false; queued = false
                    Task { await capture.start(exercise: (store.state.motionExercise ?? .dumbbellCurl).rawValue) }
                }.buttonStyle(QuietButtonStyle()).disabled(store.state.motionOptIn != true)
            }
        }
        .navigationTitle(L10n.s("Motion"))
        .task {
            if !capture.active, capture.latest != nil, capture.queuedRecordID != capture.latest?.id {
                try? capture.sendLatest()
            }
        }
        .alert(L10n.s("Motion test"), isPresented: Binding(get: { capture.error != nil }, set: { if !$0 { capture.error = nil } })) {
            Button(L10n.s("OK")) { capture.error = nil }
        } message: { Text(capture.error ?? "") }
        .confirmationDialog(L10n.s("Delete this Watch replay?"), isPresented: $deleting) {
            Button(L10n.s("Delete"), role: .destructive) {
                do { try capture.deleteLatest(); readyForNew = true; queued = false }
                catch { capture.error = error.localizedDescription }
            }
        }
        .onChange(of: capture.active) { _, active in if !active { readyForNew = false } }
    }
}
