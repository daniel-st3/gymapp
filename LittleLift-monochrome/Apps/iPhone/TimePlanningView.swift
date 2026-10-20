import SwiftUI

struct TimePlanningView: View {
    let store: PhoneStore
    @State private var useFinishTime = false
    @State private var minutes = 45
    @State private var finish = Date().addingTimeInterval(2700)
    @State private var saved = false
    @State private var removed = false
    var body: some View {
        LiftForm {
            Section(L10n.s("Available time")) {
                Toggle(L10n.s("Choose finish time"), isOn: $useFinishTime)
                if useFinishTime { DatePicker(L10n.s("Finish by"), selection: $finish, in: Date()...Date().addingTimeInterval(21600), displayedComponents: [.hourAndMinute]) }
                else { Stepper(L10n.s("\(minutes) minutes"), value: $minutes, in: 5...360, step: 5) }
                Button(saved ? L10n.s("Time saved and sent") : L10n.s("Apply to today’s workout")) {
                    do { try store.setTimeBudget(TimeBudget(durationMinutes: useFinishTime ? nil : minutes, finishAt: useFinishTime ? finish : nil)); saved = true; removed = false }
                    catch { store.error = error.localizedDescription }
                }
                if store.state.plan?.timeBudget != nil {
                    Button(L10n.s("Remove time target")) { do { try store.setTimeBudget(nil); saved = false; removed = true } catch { store.error = error.localizedDescription } }
                }
                if removed { Text(L10n.s("Time target removed from the saved workout.")).font(.caption) }
            }
            if let plan = store.state.plan, let preview = try? WorkoutSession(plan: plan) {
                Section(L10n.s("Estimated session")) {
                    Text(WorkoutPace.remaining(preview, history: store.state.effectiveSessions).text)
                    Text(L10n.s("Based on matched Log-tap intervals, including setup and exercise time. With limited history the range is broad. It is not measured rest or a promised finish time.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L10n.s("Shortening rules")) {
                Text(L10n.s("Edit priorities and approve optional exercises in Routines. During a workout, open … → Adjust workout on Watch to review a shorter remainder. Only untouched optional exercises after the current exercise may be omitted. Loads, reps and required rest stay unchanged."))
                Text(L10n.s("An active Watch workout retains the time target chosen before it started.")).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle(L10n.s("Available time")).navigationBarTitleDisplayMode(.inline)
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
