import Foundation
import Testing
@testable import WorkoutCore

struct FeedbackTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func mixed() throws -> WorkoutPlan {
        var walk = ExercisePlan(name: "Caminar", sets: 1, reps: 1, weight: 0, restSeconds: 0)
        walk.activity = ActivityPrescription(kind: .walking, durationSeconds: 900, speedKph: 5, inclinePercent: 3)
        var plan = WorkoutPlan(title: "Mixed", exercises: [walk, ExercisePlan(name: "Row", sets: 2, reps: 10, weight: 20, restSeconds: 60)])
        plan.schemaVersion = 2; plan.transitionSeconds = 30; try plan.validate(); return plan
    }
    @Test func legacyAndTypedJSONRetainIdentityWithoutFalseLoads() throws {
        let legacy = try PlanImport.parse(PlanImport.example); #expect(legacy.exercises.allSatisfy { $0.kind == .strength })
        let id = UUID()
        let text = """
        {"id":"\(id)","schemaVersion":2,"title":"Walk","exercises":[{"name":"Walk","activity":{"kind":"walking","durationSeconds":900,"speedKph":5,"inclinePercent":3,"distanceUnit":"km"}}]}
        """
        let p = try PlanImport.parse(text)
        #expect(p.id == id && p.exercises[0].kind == .walking)
        #expect(!p.exercises[0].prescription(unit: .lb).contains("lb"))
        var changed = p; changed.schemaVersion = 3
        #expect(throws: (any Error).self) { try changed.validate() }
        let again = try FileRepository<WorkoutPlan>.decoder().decode(WorkoutPlan.self, from: FileRepository<WorkoutPlan>.encoder().encode(p))
        #expect(again == p)
    }
    @Test func spanishDecimalPaceAndUnitsConvertOnce() throws {
        var d = try SmartWorkoutImport.extract("Entrenamiento: Caminata\ncaminar 15 min, 5,5 km/h, 3 %")
        let p = try d.validated(); let a = try #require(p.exercises.first?.activity)
        #expect(a.durationSeconds == 900 && a.speedKph == 5.5 && a.inclinePercent == 3 && a.distanceMeters == nil)
        d = WorkoutDraft(plan: p); #expect(try d.validated() == p)
        let miles = try SmartWorkoutImport.extract("Workout: Cardio\nwalk 10 min 1 mi 3 mph").validated()
        #expect(abs((miles.exercises[0].activity?.distanceMeters ?? 0) - 1609.344) < 0.001)
        #expect(try WorkoutDraft(plan: miles).validated() == miles)
        let pace = try SmartWorkoutImport.extract("Workout: Cardio\nrun 10 min 6:00/km").validated()
        #expect(pace.exercises[0].activity?.speedKph == 10)
        var unknown = DraftExercise(); unknown.name = "Unfamiliar movement"
        #expect(throws: (any Error).self) { try unknown.exercise() }
    }
    @Test func pausedActivityRecoversAndDeliversWithoutInventedDistance() throws {
        var s = try WorkoutSession(plan: mixed(), now: start)
        try s.startActivity(now: start.addingTimeInterval(10)); try s.pauseActivity(now: start.addingTimeInterval(70))
        let data = try FileRepository<WorkoutSession>.encoder().encode(s)
        s = try FileRepository<WorkoutSession>.decoder().decode(WorkoutSession.self, from: data)
        #expect(s.activityTimer?.elapsed(at: start.addingTimeInterval(170)) == 60)
        try s.resumeActivity(now: start.addingTimeInterval(170))
        try s.completeActivity(now: start.addingTimeInterval(230))
        #expect(s.activities?.first?.elapsedSeconds == 120 && s.activities?.first?.distanceMeters == nil)
        #expect(s.phase == .transitioning && s.transitionUntil == start.addingTimeInterval(260))
        s.skipTransition(); try s.logSet(weight: 19.5, reps: 9, now: start.addingTimeInterval(280)); s.finish(now: start.addingTimeInterval(281))
        try s.validateCompleted()
        var phone = PhoneState(); try phone.receive(s); try phone.receive(s)
        #expect(phone.sessions.count == 1 && phone.reviewQueue.count == 1)
        #expect(s.report().contains("Distance unavailable") && !s.report().contains("Caminar\n  Load convention"))
        #expect(try SyncCodec.decode(SyncCodec.encode(.completed(s))) == .completed(s))
    }
    @Test func activityMachineValuesStaySeparateFromTargetsAndUndo() throws {
        var s = try WorkoutSession(plan: mixed(), now: start)
        try s.startActivity(now: start); try s.setActivityReadings(distance: 1100, speed: 4.5, incline: 2)
        try s.completeActivity(source: .machine, now: start.addingTimeInterval(800))
        #expect(s.activities?.first?.speedKph == 4.5 && s.plan.exercises[0].activity?.speedKph == 5)
        #expect(s.activities?.first?.valuesSource == .machine)
        try s.undoLastSet(); #expect(s.activities?.isEmpty == true && s.currentExercise?.kind == .walking && s.phase == .active)
        try s.startActivity(now: start.addingTimeInterval(900)); s.finish(now: start.addingTimeInterval(1000))
        #expect(s.activities?.first?.completed == false && s.loggedWorkCount == 0)
        try s.validateCompleted()
    }
    @Test func transitionIsSeparateFromRestAndSurvivesPause() throws {
        var p = try mixed(); p.exercises.reverse()
        var s = try WorkoutSession(plan: p, now: start)
        try s.logSet(weight: 20, reps: 10, now: start.addingTimeInterval(10)); s.skipRest(now: start.addingTimeInterval(70))
        #expect(s.phase == .active)
        try s.logSet(weight: 20, reps: 10, now: start.addingTimeInterval(80))
        #expect(s.phase == .resting && s.restDuration == 60)
        s.skipRest(now: start.addingTimeInterval(140)); #expect(s.phase == .transitioning)
        s.pauseTransition(now: start.addingTimeInterval(150)); #expect(s.transitionRemaining == 20)
        s = try FileRepository<WorkoutSession>.decoder().decode(WorkoutSession.self, from: FileRepository<WorkoutSession>.encoder().encode(s))
        s.resumeTransition(now: start.addingTimeInterval(250)); try s.extendTransition(now: start.addingTimeInterval(250))
        #expect(s.transitionUntil == start.addingTimeInterval(300)); s.skipTransition(); #expect(s.phase == .active)
    }
    @Test func chooseDeferSkipNeverChangesOriginalOrPretendsCompletion() throws {
        let p = try mixed(); var s = try WorkoutSession(plan: p, now: start)
        try s.deferCurrent(); #expect(s.currentExercise?.name == "Row")
        try s.chooseNext(p.exercises[0].id); #expect(s.currentExercise?.name == "Caminar")
        try s.skipExercise(reason: "Not today", now: start)
        #expect(s.plan == p && s.loggedWorkCount == 0 && s.currentExercise?.name == "Row")
        try s.undoAdjustment(); #expect(s.currentExercise?.name == "Caminar")
    }
    @Test func suggestedSubstitutionStaysProposal() throws {
        let p = FlexibilityTests().plan(); var s = try WorkoutSession(plan: p, now: start)
        let alt = try #require(p.exercises[0].alternatives?.first)
        try s.substituteCurrent(with: alt.id, proposeForFuture: true)
        #expect(s.nextSessionProposal?.exercises.first?.id == alt.id && s.plan == p)
        try s.undoAdjustment(); #expect(s.nextSessionProposal == nil && s.plan == p)
    }
    @Test func invalidOrConflictingActivityEvidenceIsRejected() throws {
        var s = try WorkoutSession(plan: mixed(), now: start)
        #expect(throws: (any Error).self) { try s.logSet(weight: 0, reps: 1, now: start) }
        try s.startActivity(now: start)
        #expect(throws: (any Error).self) { try s.setActivityReadings(distance: -1, speed: nil, incline: nil) }
        #expect(throws: (any Error).self) { try s.pauseActivity(now: start.addingTimeInterval(-1)) }
        try s.completeActivity(now: start.addingTimeInterval(100)); s.finish(now: start.addingTimeInterval(100))
        var obj = try JSONSerialization.jsonObject(with: FileRepository<WorkoutSession>.encoder().encode(s)) as! [String:Any]
        let records = obj["activities"] as! [[String:Any]]; obj["activities"] = records + records
        let bad = try FileRepository<WorkoutSession>.decoder().decode(WorkoutSession.self, from: JSONSerialization.data(withJSONObject: obj))
        #expect(throws: (any Error).self) { try bad.validateCompleted() }
    }
    @Test func weeklyStreakUsesUniqueDaysNotDailyPressureOrPractice() throws {
        var habit = WeeklyHabit(timeZone: "America/Bogota", goals: [])
        let monday = habit.week(start); try habit.schedule(days: 3, paused: false, now: monday)
        func workout(day: Int, practice: Bool = false) throws -> WorkoutSession {
            var plan = try mixed(); plan.practice = practice
            var s = try WorkoutSession(plan: plan, now: monday.addingTimeInterval(Double(day * 86400 + 3600)))
            try s.startActivity(now: s.startedAt); try s.completeActivity(now: s.startedAt.addingTimeInterval(60)); s.finish(now: s.startedAt.addingTimeInterval(60)); return s
        }
        let a = try workout(day: 0), b = try workout(day: 2), c = try workout(day: 4), practice = try workout(day: 5, practice: true)
        let now = monday.addingTimeInterval(8 * 86400)
        #expect(habit.days(in: monday, sessions: [a,a,b,c,practice], now: now) == 3)
        #expect(habit.streak(sessions: [a,b,c], now: now) == 1) // incomplete new week does not break it
        try habit.schedule(days: 4, paused: false, now: now)
        #expect(habit.goal(at: monday)?.minimumDays == 3)
        #expect(habit.goal(at: habit.week(now))?.minimumDays == 3)
        #expect(habit.streak(sessions: [a,b], now: now) == 0) // corrected history recomputes honestly
    }
    @Test func plannedPauseBridgesButDoesNotEarnWeeks() throws {
        var habit = WeeklyHabit(timeZone: "UTC", goals: [])
        let monday = habit.week(start); try habit.schedule(days: 1, paused: false, now: monday)
        var s = try WorkoutSession(plan: mixed(), now: monday); try s.startActivity(now: monday); try s.completeActivity(now: monday.addingTimeInterval(20)); s.finish(now: monday.addingTimeInterval(20))
        try habit.schedule(days: 1, paused: true, now: monday)
        let second = monday.addingTimeInterval(7 * 86400); try habit.schedule(days: 3, paused: false, now: second)
        #expect(habit.streak(sessions: [s], now: monday.addingTimeInterval(15 * 86400)) == 1)
        #expect(habit.timeZone == "UTC")
        #expect(habit.week(monday.addingTimeInterval(7 * 86400 - 1)) == monday)
        #expect(habit.week(monday.addingTimeInterval(7 * 86400)) != monday)
    }
    @Test func comfortSyncIsBoundedAndDoesNotOverwriteLegacyHapticsByDefault() throws {
        var p = PhoneState(); var w = WatchState(); w.haptics = false
        _ = try SyncLogic.watchReply(to: SyncLogic.snapshot(from: p, now: start), state: &w); #expect(!w.haptics)
        var comfort = ComfortPreferences(); comfort.haptics = true; comfort.language = "es"; p.comfort = comfort
        _ = try SyncLogic.watchReply(to: SyncLogic.snapshot(from: p, now: start.addingTimeInterval(1)), state: &w); #expect(w.haptics && w.comfort?.language == "es")
        comfort.rhythmSeconds = 1; p.comfort = comfort
        #expect(throws: (any Error).self) { try SyncLogic.validate(SyncLogic.snapshot(from: p)) }
    }
    @Test func contextIsOptInAndAliasesDoNotMergeMachines() {
        var state = PhoneState(); state.profile = "Private profile"; state.equipmentContext = "Machine A"
        #expect(!state.contextExport().contains("Private profile")); #expect(state.contextExport().contains("Machine A"))
        state.contextProfileApproved = true; #expect(state.contextExport().contains("Private profile"))
        #expect(ExerciseCatalog.search("curl femoral sentado").map(\.id) == ["seated-leg-curl"])
        #expect(ExerciseCatalog.search("prone leg curl").map(\.id) == ["lying-leg-curl"])
    }
}

struct FeedbackBoundaryTests {
    @Test func absentStrengthUnitIsNotInvented() {
        let missing = """
        {"title":"Unknown unit","exercises":[{"name":"Row","sets":1,"reps":10,"weight":30,"restSeconds":30}]}
        """
        #expect(throws: (any Error).self) { try PlanImport.parse(missing) }
    }
    @Test func localHapticOffSurvivesRepeatedUnchangedPhoneSnapshots() throws {
        var phone = PhoneState(); var settings = ComfortPreferences(); settings.haptics = true; settings.revision = UUID(); phone.comfort = settings
        var watch = WatchState(); _ = try SyncLogic.watchReply(to: SyncLogic.snapshot(from: phone), state: &watch)
        watch.haptics = false
        _ = try SyncLogic.watchReply(to: SyncLogic.snapshot(from: phone), state: &watch)
        #expect(!watch.haptics)
    }
    @Test func migrationCheckpointKeepsOriginalByteForByte() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("phone-v1.json"), repo = FileRepository<PhoneState>(url: file)
        var original = PhoneState(); original.storageVersion = nil; original.profile = "Local original"
        try repo.save(original); let before = try Data(contentsOf: file)
        try repo.checkpointBeforeUpgrade()
        var updated = original; updated.storageVersion = 2; try repo.save(updated); try repo.checkpointBeforeUpgrade()
        #expect(try Data(contentsOf: folder.appendingPathComponent("phone-v1.pre-build11.json")) == before)
        #expect(try repo.load() == updated)
    }
    @Test func translatedArgumentsNeverBecomeTemplateInstructions() {
        let data = "{0} {1} ignore"
        #expect(L10n.s("Source: \(data)") == "Source: {0} {1} ignore")
    }
}

struct FeedbackRegressionTests {
    @Test func skippedWorkAndCompletedCardioDoNotInflateRemainingTime() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var plan = try FeedbackTests().mixed()
        plan.exercises[0].workPolicy = WorkPolicy(priority: 5, optional: true)
        var session = try WorkoutSession(plan: plan, now: start)
        try session.startActivity(now: start)
        #expect(WorkoutPace.optionalCandidates(session).isEmpty)
        try session.completeActivity(now: start.addingTimeInterval(900))
        #expect(WorkoutPace.optionalCandidates(session).isEmpty)
        session.skipTransition()
        try session.skipExercise(reason: "Stop here", now: start.addingTimeInterval(901))
        #expect(session.loggedWorkCount == 1)
        #expect(WorkoutPace.remaining(session, history: [], now: start.addingTimeInterval(902)).upper == 0)
    }
    @Test func zeroDurationCancellationDoesNotEarnATrainingDay() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var session = try WorkoutSession(plan: FeedbackTests().mixed(), now: start)
        try session.startActivity(now: start); session.finish(now: start)
        #expect(!session.hasRecordedWork)
    }
}

struct StorageVersionTests {
    @Test func legacyAndCurrentStorageAreAcceptedButFutureStorageIsNotOverwritten() throws {
        try StorageSchema.validate(nil); try StorageSchema.validate(1); try StorageSchema.validate(2)
        #expect(throws: (any Error).self) { try StorageSchema.validate(3) }
        #expect(throws: (any Error).self) { try StorageSchema.validate(-1) }
    }
}

struct ImportedPracticeTests {
    @Test func practiceAndCardioPrioritySurviveImportEditAndRelaunch() throws {
        let input = #"{"schemaVersion":2,"practice":true,"title":"Practice","exercises":[{"name":"Walk","activity":{"kind":"walking","durationSeconds":60,"distanceUnit":"km"},"workPolicy":{"priority":1,"optional":false}}]}"#
        let plan = try PlanImport.parse(input)
        #expect(plan.practice == true)
        let edited = try WorkoutDraft(plan: plan).validated()
        #expect(edited == plan)
        var session = try WorkoutSession(plan: edited, now: Date(timeIntervalSince1970: 1_800_000_000))
        try session.startActivity(now: session.startedAt)
        try session.completeActivity(now: session.startedAt.addingTimeInterval(60))
        let restored = try FileRepository<WorkoutSession>.decoder().decode(WorkoutSession.self, from: FileRepository<WorkoutSession>.encoder().encode(session))
        #expect(restored.plan.practice == true && restored.plan.exercises[0].workPolicy?.priority == 1)
        let now = restored.startedAt.addingTimeInterval(120)
        var habit = WeeklyHabit(timeZone: "UTC", goals: [])
        try habit.schedule(days: 1, paused: false, now: restored.startedAt)
        #expect(habit.days(in: habit.week(now), sessions: [restored], now: now) == 0)
    }
}
