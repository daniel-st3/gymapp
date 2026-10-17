import SwiftUI

struct WorkoutEvidenceReviewView: View {
    let session: WorkoutSession
    let store: PhoneStore
    @Environment(\.dynamicTypeSize) private var textSize
    private var review: WorkoutEvidenceReview { WorkoutEvidenceReview(session: session, history: store.state.sessions) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LiftPageHeading(title: session.plan.title, detail: L10n.s("Automatic review · saved on this iPhone"))
                if textSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 16) { reviewMetrics }
                } else { HStack(alignment: .top, spacing: 16) { reviewMetrics } }
                ForEach(session.executionExercises) { exercise in
                    LiftSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(exercise.name).font(LiftType.heading)
                            Text(L10n.s("Target · \(exercise.prescription(unit: session.plan.unit))")).font(.subheadline).foregroundStyle(.secondary)
                            if let convention = exercise.loadConvention { Text(convention.label).font(.caption).foregroundStyle(.secondary) }
                            if exercise.kind == .strength {
                                let items = review.comparisons.filter { $0.exercise.id == exercise.id }
                                if items.isEmpty { Text(L10n.s("Not completed")).font(.callout) }
                                ForEach(items) { item in
                                    Divider()
                                    Text(L10n.s("Set \(item.entry.setNumber) · confirmed: \(WorkoutSession.number(item.entry.weight)) \(session.plan.unit.rawValue) × \(item.entry.reps)"))
                                        .font(.callout).accessibilityIdentifier("review.set.\(item.entry.setNumber)")
                                    if item.previous != nil { Text(review.comparisonText(item)).font(.caption).foregroundStyle(.secondary) }
                                    if let id = item.previousSessionID, let previous = store.state.sessions.first(where: { $0.id == id }) {
                                        NavigationLink { SessionDetailView(session: previous) } label: {
                                            Label(L10n.s("View earlier workout"), systemImage: "clock.arrow.circlepath").font(.caption).frame(minHeight: 44)
                                        }
                                    }
                                    if let interval = session.loggingInterval(before: item.entry) {
                                        Text(L10n.s("Log-tap interval: \(WorkoutSession.number(interval)) s · includes exercise time")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if let missing = items.first(where: { $0.previous == nil }) {
                                    Text(review.comparisonText(missing)).font(.caption).foregroundStyle(.secondary)
                                }
                            } else if let result = session.activities?.first(where: { $0.exerciseID == exercise.id }) {
                                Text(result.summary(unit: exercise.activity?.distanceUnit ?? .km)).font(.callout)
                            } else { Text(L10n.s("Not completed")).font(.callout) }
                        }.padding(18)
                    }
                }
                if !session.observationEvidence.isEmpty {
                    LiftSection(title: L10n.s("Coach observations")) {
                        ForEach(session.observationEvidence) { evidence in
                            NavigationLink { ObservationDetailView(session: session, evidence: evidence) } label: {
                                LiftSurface { LiftMenuRow(title: evidence.title, symbol: "text.bubble", detail: evidence.detail) }
                            }
                        }
                    }
                }
                DisclosureGroup(L10n.s("How this review is calculated")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.s("Ready automatically when your workout is saved. Calculated locally from your records; no ChatGPT or internet required."))
                        Text(review.timingNote)
                    }.font(.caption).padding(.vertical, 8)
                }
                NavigationLink { SessionDetailView(session: session) } label: { Label(L10n.s("Full record & original prescription"), systemImage: "list.bullet.rectangle").frame(minHeight: 44) }
                if let proposal = session.nextSessionProposal {
                    NavigationLink(L10n.s("Review substitution for next time")) { WorkoutEditorView(store: store, initial: WorkoutDraft(plan: proposal), routineID: nil) }
                }
                ShareLink(item: review.report()) { Label(L10n.s("Share review with my coach"), systemImage: "square.and.arrow.up").frame(minHeight: 44) }
            }.padding(24)
        }.buttonStyle(.plain).background(.black).navigationTitle(L10n.s("Workout review")).navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private var reviewMetrics: some View {
        LiftStat(value: String(review.strengthSets), label: L10n.s("Strength sets recorded"))
        if review.timedSegments > 0 { LiftStat(value: String(review.timedSegments), label: L10n.s("Timed segments recorded")) }
        LiftStat(value: String(review.matchedSets), label: L10n.s("With an earlier match"))
    }
}
