import AppIntents

struct PrepareWorkoutReviewIntent: AppIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let title: LocalizedStringResource = "Prepare Workout Review"
    static let description = IntentDescription("Get the training profile and recent workout logs you saved in Little Lift, with instructions for ChatGPT.")
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try PhoneStore.shared.prepareReview())
    }
}

struct SaveWorkoutReviewIntent: AppIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let title: LocalizedStringResource = "Save Workout Review"
    static let description = IntentDescription("Save ChatGPT’s analysis and proposed plan for review in Little Lift. Does not replace today’s workout until accepted.")
    @Parameter(title: "Review JSON") var reviewJSON: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try PhoneStore.shared.saveReview(reviewJSON)
        return .result(dialog: "Saved. Open Little Lift to review your next workout.")
    }
}

struct ImportWorkoutIntent: AppIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let title: LocalizedStringResource = "Import Workout"
    static let description = IntentDescription("Stage a workout JSON plan for review. Accept it in Little Lift before sending to Apple Watch.")
    @Parameter(title: "Workout JSON") var workoutJSON: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try PhoneStore.shared.proposeImport(workoutJSON)
        return .result(dialog: "Proposal saved. Open Little Lift to review its observations and accept the workout.")
    }
}

struct WorkoutShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PrepareWorkoutReviewIntent(), phrases: ["Prepare my workout review in \(.applicationName)"],
                    shortTitle: "Prepare review", systemImageName: "dumbbell")
    }
}

struct CancelWorkoutReviewIntent: AppIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let title: LocalizedStringResource = "Cancel Workout Review"
    static let description = IntentDescription("Cancel the running review so a delayed model result cannot be saved.")
    @MainActor func perform() async throws -> some IntentResult {
        if let job = PhoneStore.shared.state.reviewQueue.first(where: { $0.status == .running }) {
            try PhoneStore.shared.endReview(job.id, cancelled: true, detail: "Cancelled from Shortcuts.")
        }
        return .result()
    }
}
