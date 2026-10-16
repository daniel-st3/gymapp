import SwiftUI

struct TimePlanningView: View {
    let store: PhoneStore
    @State private var useFinishTime = false
    @State private var minutes = 45
    @State private var finish = Date().addingTimeInterval(2700)
    @State private var saved = false
    var body: some View {
        LiftForm {
            Section("Available time") {
                Toggle("Choose finish time", isOn: $useFinishTime)
                if useFinishTime { DatePicker("Finish by", selection: $finish, in: Date()...Date().addingTimeInterval(21600), displayedComponents: [.hourAndMinute]) }
                else { Stepper("\(minutes) minutes", value: $minutes, in: 5...360, step: 5) }
                Button(saved ? "Time saved and sent" : "Apply to today’s workout") {
                    do { try store.setTimeBudget(TimeBudget(durationMinutes: useFinishTime ? nil : minutes, finishAt: useFinishTime ? finish : nil)); saved = true }
                    catch { store.error = error.localizedDescription }
                }
                Button("Remove time target") { do { try store.setTimeBudget(nil); saved = false } catch { store.error = error.localizedDescription } }
            }
            if let plan = store.state.plan, let preview = try? WorkoutSession(plan: plan) {
                Section("Estimated session") {
                    Text(WorkoutPace.remaining(preview, history: store.state.sessions).text)
                    Text("Based on matched Log-tap intervals, including setup and exercise time. With limited history the range is broad. It is not measured rest or a promised finish time.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Shortening rules") {
                Text("Edit priorities and approve optional exercises in Routines. During a workout, open … → Adjust workout on Watch to review a shorter remainder. Only untouched optional exercises after the current exercise may be omitted. Loads, reps and required rest stay unchanged.")
                Text("An active Watch workout retains the time target chosen before it started.").foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle("Available time").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let budget = store.state.plan?.timeBudget {
                    if let deadline = budget.finishAt { finish = max(.now, deadline); useFinishTime = true }
                    if let duration = budget.durationMinutes { minutes = duration; useFinishTime = false }
                }
            }
            .onChange(of: minutes) { saved = false }
            .onChange(of: finish) { saved = false }
            .onChange(of: useFinishTime) { saved = false }
    }
}
