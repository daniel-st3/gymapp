import SwiftUI

struct WorkoutProgressLine: View {
    let session: WorkoutSession
    var body: some View {
        let finished = session.executionExercises.filter { session.completedCount(for: $0) == $0.sets }.count
        HStack(spacing: 5) {
            Text(L10n.s("\(session.loggedWorkCount)/\(session.plan.totalSets)"))
            Text(L10n.s("· \(finished)/\(session.plan.exercises.count) exercises"))
        }.watchText(.caption).foregroundStyle(.secondary).monospacedDigit()
            .accessibilityLabel(L10n.s("\(session.loggedWorkCount) of \(session.plan.totalSets) sets or segments completed; \(finished) of \(session.plan.exercises.count) exercises completed"))
    }
}

struct TimedActivityView: View {
    let store: WatchStore
    let session: WorkoutSession
    let exercise: ExercisePlan
    @State private var readings = false
    var body: some View {
        WatchPage {
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.name).watchText(.body).lineLimit(2)
                WorkoutProgressLine(session: session)
                Text(exercise.activity?.summary ?? "").watchText(.caption).foregroundStyle(.secondary)
                if let timer = session.activityTimer {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = Int(timer.elapsed(at: context.date))
                        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).font(.title2.weight(.light)).monospacedDigit()
                    }
                    if timer.paused { Text(L10n.s("Paused")).watchText(.caption).foregroundStyle(.secondary) }
                    Button(L10n.s("Machine readings · optional")) { readings = true }.watchText(.caption).buttonStyle(QuietTextButtonStyle())
                } else { Text(L10n.s("Start when you begin moving.")).watchText(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            if let timer = session.activityTimer {
                HStack(spacing: 6) {
                    Button(timer.paused ? L10n.s("Resume") : L10n.s("Pause")) { store.perform { try store.activityAction(timer.paused ? .resume : .pause) } }
                    Button(L10n.s("Done")) { store.perform { try store.activityAction(.done) } }
                }.buttonStyle(QuietButtonStyle())
            } else {
                Button(L10n.s("Start activity")) { store.perform { try store.activityAction(.start) } }.buttonStyle(QuietButtonStyle(prominent: true))
            }
        }.sheet(isPresented: $readings) { ActivityReadingsView(store: store, unit: exercise.activity?.distanceUnit ?? .km) }
    }
}

struct ActivityReadingsView: View {
    let store: WatchStore
    let unit: DistanceUnit
    @Environment(\.dismiss) private var dismiss
    @State private var distance = ""
    @State private var speed = ""
    @State private var incline = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Text(L10n.s("Enter displayed machine results. Leave unknown values empty.")).watchText(.caption)
                TextField(L10n.s("Distance · \(unit.rawValue)"), text: $distance)
                TextField(unit == .km ? L10n.s("Speed · km/h") : L10n.s("Speed · mph"), text: $speed)
                TextField(L10n.s("Incline · %"), text: $incline)
                if let error { Text(error).watchText(.caption) }
                Button(L10n.s("Save readings")) {
                    do {
                        func number(_ text: String) throws -> Double? {
                            if text.isEmpty { return nil }
                            guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite else { throw WorkoutError.invalidInput(L10n.s("Enter a number or leave it empty.")) }
                            return value
                        }
                        try store.activityReadings(distance: try number(distance).map { $0 * unit.meters }, speed: try number(speed).map { $0 * (unit == .mi ? 1.609344 : 1) }, incline: try number(incline))
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            }.navigationTitle(L10n.s("Machine results"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.s("Cancel")) { dismiss() } } }
                .onAppear {
                    let timer = store.state.session?.activityTimer
                    distance = timer?.distanceMeters.map { String($0 / unit.meters) } ?? ""
                    speed = timer?.speedKph.map { String($0 / (unit == .mi ? 1.609344 : 1)) } ?? ""
                    incline = timer?.inclinePercent.map(String.init(describing:)) ?? ""
                }
        }
    }
}

struct TransitionView: View {
    let store: WatchStore
    let session: WorkoutSession
    var body: some View {
        WatchPage {
            VStack(alignment: .leading, spacing: 5) {
                WaterReminderView(store: store)
                Text(L10n.s("Prepare next exercise")).watchText(.caption).foregroundStyle(.secondary)
                Text(session.currentExercise?.name ?? "").watchText(.body).lineLimit(2)
                WorkoutProgressLine(session: session)
                if let until = session.transitionUntil {
                    RestClock(deadline: until, duration: Double(session.plan.transitionSeconds ?? 30), compact: true)
                    Button(L10n.s("Pause timer")) { store.perform { try store.transitionAction(.pause) } }.watchText(.caption).buttonStyle(QuietTextButtonStyle())
                } else {
                    Text(L10n.s("Paused · \(Int(session.transitionRemaining ?? 0)) sec")).watchText(.secondary)
                    Button(L10n.s("Resume timer")) { store.perform { try store.transitionAction(.resume) } }.watchText(.caption).buttonStyle(QuietTextButtonStyle())
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            HStack(spacing: 6) {
                Button(L10n.s("+30 sec")) { store.perform { try store.transitionAction(.extend) } }
                Button(L10n.s("Ready")) { store.perform { try store.transitionAction(.done) } }
            }.buttonStyle(QuietButtonStyle())
        }
    }
}
