import SwiftUI

struct ComfortSettingsView: View {
    let store: PhoneStore
    @State private var preferences = ComfortPreferences()
    @State private var saving = false
    var body: some View {
        LiftForm {
            Section(L10n.s("Language")) {
                Picker(L10n.s("App language"), selection: $preferences.language) {
                    Text(L10n.s("System")).tag(String?.none); Text(L10n.s("Español")).tag(Optional("es")); Text(L10n.s("English")).tag(Optional("en"))
                }
                Text(L10n.s("Language does not change units or your weekly time zone.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.s("Haptics")) {
                Toggle(L10n.s("App haptics"), isOn: Binding(get: { preferences.haptics ?? true }, set: { preferences.haptics = $0 }))
                Toggle(L10n.s("Rest finished"), isOn: $preferences.restHaptics)
                Toggle(L10n.s("Rhythm guide"), isOn: $preferences.rhythmEnabled)
                if preferences.rhythmEnabled { Stepper(L10n.s("Pulse every \(preferences.rhythmSeconds) seconds"), value: $preferences.rhythmSeconds, in: 2...10) }
                Text(L10n.s("Rhythm is a metronome, not repetition detection. It never changes your actual count. Pulses can interrupt Watch heart-rate sampling. There is no app-controlled vibration intensity.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.s("Quiet reminders")) {
                Toggle(L10n.s("Water reminder"), isOn: Binding(get: { preferences.waterMinutes != nil }, set: { preferences.waterMinutes = $0 ? 30 : nil }))
                if preferences.waterMinutes != nil {
                    Stepper(L10n.s("Every \(preferences.waterMinutes ?? 30) min"), value: Binding(get: { preferences.waterMinutes ?? 30 }, set: { preferences.waterMinutes = $0 }), in: 10...120, step: 5)
                }
                Text(L10n.s("One visual reminder during rest or machine changes. Snooze or dismiss on Watch. No background delivery or water amount is prescribed.")).font(.caption).foregroundStyle(.secondary)
                Toggle(L10n.s("Quiet mode · no feedback messages"), isOn: $preferences.quietFeedback)
            }
            Section { Button(L10n.s("Save preferences")) {
                do { try store.setComfort(preferences); saving = true } catch { store.error = error.localizedDescription }
            }; if saving { Text(L10n.s("Saved. Preferences sync to Watch.")).font(.caption) } }
        }.navigationTitle(L10n.s("Training preferences")).navigationBarTitleDisplayMode(.inline)
            .onAppear { preferences = store.state.comfort ?? ComfortPreferences() }
            .onChange(of: preferences) { saving = false }
    }
}
struct WeeklyHabitView: View {
    let store: PhoneStore
    @State private var days = 3
    @State private var paused = false
    @State private var saved = false
    var body: some View {
        LiftForm {
            Section(L10n.s("A flexible week")) {
                Stepper(days == 1 ? L10n.s("Minimum 1 day") : L10n.s("Minimum \(days) days"), value: $days, in: 1...7)
                Toggle(L10n.s("Planned pause"), isOn: $paused)
                Text(L10n.s("Monday–Sunday. A completed workout with recorded work counts once per day. Practice and imported records do not count. Rest days are allowed.")).font(.callout)
                Text(L10n.s("Your time zone is fixed when you enable the goal. Later changes start next Monday; previous weeks keep their rule. Paused weeks preserve continuity without earning a week.")).font(.caption).foregroundStyle(.secondary)
                Button(L10n.s("Save weekly goal")) {
                    do { try store.setWeeklyGoal(days: days, paused: paused); saved = true } catch { store.error = error.localizedDescription }
                }
                if saved { Text(L10n.s("Saved. Check the effective week below.")).font(.caption) }
            }
            if let habit = store.state.weeklyHabit {
                Section(habit.timeZone) {
                    ForEach(habit.goals.sorted { $0.effectiveWeek > $1.effectiveWeek }) { rule in
                        Text(L10n.s("\(rule.effectiveWeek.formatted(date: .abbreviated, time: .omitted)) · \(rule.paused ? L10n.s("Paused") : (rule.minimumDays == 1 ? L10n.s("1 day") : L10n.s("\(rule.minimumDays) days")))"))
                    }
                }
            }
        }.navigationTitle(L10n.s("Weekly goal")).navigationBarTitleDisplayMode(.inline)
            .onAppear { if let latest = store.state.weeklyHabit?.goals.max(by: { $0.effectiveWeek < $1.effectiveWeek }) { days = latest.minimumDays; paused = latest.paused } }
    }
}
struct HabitSummaryView: View {
    let store: PhoneStore
    let now: Date
    var body: some View {
        LiftSurface {
            if let habit = store.state.weeklyHabit, let rule = habit.goal(at: habit.week(now)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(rule.paused ? L10n.s("Planned pause") : L10n.s("\(habit.days(in: habit.week(now), sessions: store.state.effectiveSessions, now: now)) / \(rule.minimumDays) training days this week")).font(LiftType.heading)
                    Text(habit.streak(sessions: store.state.effectiveSessions, now: now) == 1 ? L10n.s("1 completed week · rest days welcome") : L10n.s("\(habit.streak(sessions: store.state.effectiveSessions, now: now)) completed weeks · rest days welcome")).font(.caption).foregroundStyle(.secondary)
                    NavigationLink(L10n.s("Edit weekly goal")) { WeeklyHabitView(store: store) }
                }.padding(18)
            } else { NavigationLink { WeeklyHabitView(store: store) } label: { LiftMenuRow(title: L10n.s("Set a flexible weekly goal"), symbol: "calendar") } }
        }
    }
}
struct CoachContextView: View {
    let store: PhoneStore
    @State private var includeProfile = false
    @State private var includeHistory = true
    @State private var equipment = ""
    @State private var preview = ""
    @State private var editing = false
    var body: some View {
        LiftForm {
            Section(L10n.s("Choose what to share")) {
                Toggle(L10n.s("Include my profile"), isOn: $includeProfile)
                Toggle(L10n.s("Include recent confirmed history"), isOn: $includeHistory)
                TextField(L10n.s("Known equipment · gym / branch optional"), text: $equipment, axis: .vertical).lineLimit(3...6)
                Text(L10n.s("Only list equipment you know. A web description does not confirm a machine at your gym. Photos and location are not sent automatically.")).font(.caption).foregroundStyle(.secondary)
                Button(L10n.s("Preview context")) {
                    do {
                        try store.saveContext(profile: includeProfile, history: includeHistory, equipment: equipment)
                        preview = store.state.contextExport(); editing = true
                    } catch { store.error = error.localizedDescription }
                }
            }
            if editing {
                Section(L10n.s("Editable export")) {
                    TextEditor(text: $preview).frame(height: 240).accessibilityLabel(L10n.s("Context to share"))
                    ShareLink(item: preview) { Label(L10n.s("Share this context"), systemImage: "square.and.arrow.up") }
                    Text(L10n.s("Choose your chat in the destination app. Opening or sharing does not confirm a message reached a specific conversation. Shortcut analysis is a separate route.")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle(L10n.s("Coach context")).navigationBarTitleDisplayMode(.inline)
            .onAppear { includeProfile = store.state.contextProfileApproved == true; includeHistory = store.state.contextHistoryApproved != false; equipment = store.state.equipmentContext ?? "" }
            .onChange(of: includeProfile) { editing = false }.onChange(of: includeHistory) { editing = false }.onChange(of: equipment) { editing = false }
    }
}
struct ExerciseHelpView: View {
    @State private var query = ""
    private var store: PhoneStore { .shared }
    var body: some View {
        LiftList {
            let saved = store.state.savedExercises(matching: query)
            if !saved.isEmpty {
                Section(L10n.s("In your saved workouts")) {
                    ForEach(saved) { reference in
                        NavigationLink {
                            LiftForm {
                                Section(reference.exercise.name) {
                                    Text(reference.plan.title).font(.caption)
                                    Text(reference.exercise.prescription(unit: reference.plan.unit))
                                    if let convention = reference.exercise.loadConvention { Text(convention.label).font(.caption) }
                                }
                                Section {
                                    Text(L10n.s("This is your saved prescription. Similar machine names do not make their loads equivalent. Availability at your gym is not confirmed.")).font(.callout)
                                }
                            }.navigationTitle(L10n.s("Saved exercise")).navigationBarTitleDisplayMode(.inline)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(reference.exercise.name)
                                Text(reference.plan.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section(L10n.s("Local exercise guide")) {
            ForEach(ExerciseCatalog.search(query)) { item in
                NavigationLink {
                    LiftForm {
                        Section { Text(item.displayName).font(LiftType.title); Text(item.translatedName); Text(item.aliases.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        Section(L10n.s("Equipment")) { Text(item.equipment) }
                        Section(L10n.s("Movement")) { Text(item.explanation) }
                        Section { Text(L10n.s("General description, not an approved substitute or a confirmed gym inventory. Keep your preferred exercise name and exact machine in your plan.")).font(.caption).foregroundStyle(.secondary) }
                    }.navigationTitle(L10n.s("Exercise help")).navigationBarTitleDisplayMode(.inline)
                } label: { VStack(alignment: .leading) { Text(item.displayName); Text(item.translatedName).font(.caption).foregroundStyle(.secondary) } }
            }
            }
            if saved.isEmpty && ExerciseCatalog.search(query).isEmpty {
                Text(L10n.s("No saved exercise or guide matches. Keep the name from your coach; an unfamiliar name does not identify a machine automatically.")).font(.callout)
            }
        }.searchable(text: $query, prompt: L10n.s("Name in Spanish or English")).navigationTitle(L10n.s("Exercise help")).navigationBarTitleDisplayMode(.inline)
    }
}
struct GettingStartedView: View {
    let store: PhoneStore
    var body: some View {
        LiftForm {
            Section(L10n.s("1 · Choose a workout")) {
                NavigationLink(L10n.s("Import text, screenshot or JSON")) { SmartImportView(store: store) }
                Button(L10n.s("Use a practice workout")) {
                    do { var plan = try PlanImport.parse(PlanImport.example); plan.title = L10n.s("Practice · upper body"); plan.practice = true; try store.acceptImportedPlan(plan); try store.completeOnboarding("plan") }
                    catch { store.error = error.localizedDescription }
                }.disabled(store.state.plan != nil)
                Text(L10n.s("Practice is excluded from weekly goals. Import always opens an editable preview before saving.")).font(.caption)
            }
            Section(L10n.s("2 · Connect your Watch")) {
                Text(store.syncMessage)
                Button(L10n.s("Send workout to Watch")) { store.sendToWatch() }.disabled(store.state.plan == nil || store.isSyncing)
                Text(L10n.s("Open Little Lift on the paired Watch. Saved workouts queue safely if your phone is away.")).font(.caption)
            }
            Section(L10n.s("3 · Train on Watch")) {
                Text(L10n.s("Start workout, confirm your actual values and log. Cardio has Start, Pause and Done. Use the branch button to defer or choose another exercise; … has details, undo and early finish."))
                Text(L10n.s("For wrist raise, check Watch Settings → General → Return to Clock → Little Lift. Enable Return to App if offered. watchOS controls dimming and foreground behavior.")).font(.caption)
                Text(L10n.s("Allow Workouts for the workout runtime. Denying it leaves manual logging available. Only one workout app can record at once.")).font(.caption)
            }
            Section(L10n.s("4 · Review when ready")) {
                NavigationLink(L10n.s("Workout reviews")) { ReviewQueueView(store: store) }
                Text(L10n.s("Every saved workout has a local review. No setup, account or connection is needed.")).font(.caption)
                NavigationLink(L10n.s("Choose coach connection")) { CoachingSettingsView(store: store) }
                NavigationLink(L10n.s("Review shared context")) { CoachContextView(store: store) }
                Text(L10n.s("Your existing chat receives explicit shares. Shortcuts needs its own setup and does not inherit that chat. A suggested plan always waits for acceptance.")).font(.caption)
            }
            Section(L10n.s("Personal installation")) {
                Text(L10n.s("Use Refresh My Devices.command on your Mac before free signing expires. It updates in place. Do not uninstall to renew: uninstalling can remove local data."))
                Text(L10n.s("This is a personal Xcode installation, not an App Store release. A website cannot install your signing profile or grant permissions for you.")).font(.caption)
            }
            Button((store.state.onboardingSteps ?? []).contains("guide") ? L10n.s("Guide completed") : L10n.s("Mark guide complete")) { do { try store.completeOnboarding("guide") } catch { store.error = error.localizedDescription } }
        }.navigationTitle(L10n.s("Start here")).navigationBarTitleDisplayMode(.inline)
    }
}
