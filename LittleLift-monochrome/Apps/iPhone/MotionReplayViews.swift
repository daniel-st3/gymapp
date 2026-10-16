import SwiftUI

struct MotionLibraryView: View {
    let store: PhoneStore
    var body: some View {
        LiftList {
            Section {
                Toggle("Enable on Watch", isOn: Binding(get: { store.state.motionOptIn == true }, set: { value in do { try store.setMotionOptIn(value) } catch { store.error = error.localizedDescription } }))
                Picker("Exercise", selection: Binding(get: { store.state.motionExercise ?? .dumbbellCurl }, set: { value in do { try store.setMotionExercise(value) } catch { store.error = error.localizedDescription } })) {
                    ForEach(MotionExercise.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            } header: { Text("Experimental") } footer: {
                Text("On Watch: … → Motion test → Start. Allow Apple’s permission request, then tap Stop. The saved replay transfers to iPhone automatically; Send on Watch retries if needed. A test lasts up to 3 minutes.")
                    .font(.footnote)
            }
            Section {
                DisclosureGroup("Before your first test") {
                    Text("If Start reports missing permission: on Watch, open Settings → Health → Apps → Little Lift and allow Workouts. Only you can grant this Apple permission.")
                    Text("Use only when no other workout app is recording. A temporary HealthKit workout provides background runtime and may affect system activity measurements. Little Lift does not save a Health workout or read Health history.")
                    Text("Wrist rotation cannot measure weight or certify technique. Repetition counts are estimates you can edit and confirm. Wrist-down continuity, battery use and counting accuracy are not yet validated.")
                    Text("Processing stays on your devices. Raw recordings are excluded from cloud backup. Ordinary workout logging does not use this experiment.")
                }
                Button("Refresh replays") { store.loadMotion() }
            }
            ForEach(store.motionRecordings) { recording in
                NavigationLink { MotionReplayDetailView(store: store, initial: recording) } label: {
                    VStack(alignment: .leading) {
                        Text(recording.exercise)
                        Text("\(Int(recording.duration))s · \(recording.status) · \(recording.confirmedReps.map { "\($0) confirmed reps" } ?? "unconfirmed")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if store.motionRecordings.isEmpty { Text("Stopped recordings sent from Watch appear here. The original stays on Watch until you delete it.").foregroundStyle(.secondary) }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle("Motion test").navigationBarTitleDisplayMode(.inline).onAppear { store.loadMotion() }
    }
}
struct MotionReplayDetailView: View {
    let store: PhoneStore
    @State private var recording: MotionRecording
    @State private var count: Int
    @State private var selectedTime = 0.0
    @State private var confirmed = false
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    init(store: PhoneStore, initial: MotionRecording) {
        self.store = store; _recording = State(initialValue: initial)
        _count = State(initialValue: initial.confirmedReps ?? initial.suggestedMarkers.count)
    }
    var body: some View {
        LiftList {
            Section("Experimental timing replay") {
                Text(recording.exercise)
                MotionTimeline(recording: recording, selectedTime: selectedTime).frame(height: 170)
                    .accessibilityLabel("Wrist rotation timeline, \(recording.suggestedMarkers.count) suggested markers, \(recording.gaps.count) sample gaps")
                Slider(value: $selectedTime, in: 0...max(1, recording.duration)).accessibilityLabel("Replay time")
                Text("\(selectedTime.formatted(.number.precision(.fractionLength(1)))) / \(recording.duration.formatted(.number.precision(.fractionLength(1)))) seconds").monospacedDigit()
                Text("Solid trace: measured wrist rotation magnitude. Thin markers: proposed repetitions. Gaps: missing sensor samples. No body-pose or technique reconstruction.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Estimates — confirm separately") {
                Text("\(recording.suggestedMarkers.count) suggested repetitions · \(recording.suggestedSets.count) possible sets")
                Text("\(recording.samples.count) samples · \(recording.gaps.count) gaps over 160 ms · status: \(recording.status)").font(.caption)
                Stepper("Confirmed repetitions: \(count)", value: $count, in: 0...200)
                Button(confirmed ? "Confirmation saved" : "Save my confirmed count") {
                    do { try recording.confirm(reps: count); try store.saveMotion(recording); confirmed = true }
                    catch { store.error = error.localizedDescription }
                }
                Text("This does not alter a logged set or its load. Raw samples and suggested markers stay separate from your confirmation.").font(.caption).foregroundStyle(.secondary)
            }
            if let start = recording.batteryStart, let end = recording.batteryEnd {
                Section("Device-reported battery") {
                    Text("\(Int(start * 100))% → \(Int(end * 100))%")
                    Text("A short run and coarse battery readings do not establish battery cost.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section { Button("Delete this local recording", role: .destructive) { deleting = true } }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle("Timing replay").navigationBarTitleDisplayMode(.inline)
            .onChange(of: count) { confirmed = false }
            .confirmationDialog("Delete this iPhone copy?", isPresented: $deleting) {
                Button("Delete recording", role: .destructive) { do { try store.deleteMotion(recording.id); dismiss() } catch { store.error = error.localizedDescription } }
            } message: { Text("This deletes the local raw samples and confirmation. A Watch copy is retained separately.") }
    }
}
private struct MotionTimeline: View {
    let recording: MotionRecording
    let selectedTime: Double
    var body: some View {
        Canvas { context, size in
            let duration = max(1, recording.duration)
            let samples = recording.samples
            let maximum = max(1, samples.map { sqrt($0.x*$0.x + $0.y*$0.y + $0.z*$0.z) }.max() ?? 1)
            var path = Path()
            // Bound rendering cost without changing stored samples or estimates.
            let stride = max(1, samples.count / 500)
            for i in Swift.stride(from: 0, to: samples.count, by: stride) {
                let s = samples[i]; let point = CGPoint(x: s.t / duration * size.width, y: size.height - sqrt(s.x*s.x+s.y*s.y+s.z*s.z) / maximum * (size.height - 8))
                if i == 0 || s.t - samples[max(0,i-stride)].t > Double(stride) * 0.1 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(.white), lineWidth: 1)
            for marker in recording.suggestedMarkers {
                let x = marker / duration * size.width
                var line = Path(); line.move(to: CGPoint(x:x,y:0)); line.addLine(to: CGPoint(x:x,y:size.height))
                context.stroke(line, with: .color(.gray.opacity(0.5)), lineWidth: 0.5)
            }
            let x = selectedTime / duration * size.width
            var cursor = Path(); cursor.move(to: CGPoint(x:x,y:0)); cursor.addLine(to: CGPoint(x:x,y:size.height))
            context.stroke(cursor, with: .color(.white), style: StrokeStyle(lineWidth: 1, dash: [3,3]))
        }.background(.black)
    }
}
