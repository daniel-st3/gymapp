import SwiftUI

struct ReviewQueueView: View {
    let store: PhoneStore
    var body: some View {
        LiftList {
            Section(L10n.s("Automatic reviews")) {
                Text(L10n.s("Every saved workout has a local review. No setup, account or connection is needed.")).font(.caption).foregroundStyle(.secondary)
                ForEach(store.state.effectiveSessions) { session in
                    NavigationLink { WorkoutEvidenceReviewView(session: session, store: store) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.plan.title)
                            Text(session.startedAt, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if store.state.effectiveSessions.isEmpty { Text(L10n.s("Completed workouts appear here after syncing from Watch.")) }
            if let saved = store.state.unlinkedCoachReviews, !saved.isEmpty {
                Section(L10n.s("Imported coach responses")) {
                    ForEach(saved.reversed()) { item in
                        NavigationLink(item.response.plan.title) { UnlinkedCoachReviewView(saved: item, store: store) }
                    }
                }
            }
            NavigationLink(L10n.s("Optional ChatGPT setup")) { OptionalCoachReviewsView(store: store) }
        }.navigationTitle(L10n.s("Workout reviews")).navigationBarTitleDisplayMode(.inline)
    }
}

private struct UnlinkedCoachReviewView: View {
    let saved: UnlinkedCoachReview
    let store: PhoneStore
    @State private var showingProposal = false
    var body: some View {
        LiftList {
            Section {
                Text(saved.response.analysis).textSelection(.enabled)
                Text(L10n.s("Imported response · not linked to a specific workout.")).font(.caption).foregroundStyle(.secondary)
                if let date = store.state.unlinkedCoachReviewsOutdatedAt, saved.savedAt <= date {
                    Text(L10n.s("Workout evidence changed. Share the updated report before using this older proposal.")).font(.caption)
                }
                Button(L10n.s("Review proposed workout")) {
                    do { try store.stageUnlinkedReview(saved.id); showingProposal = true }
                    catch { store.error = error.localizedDescription }
                }
            }
        }.navigationTitle(L10n.s("Saved coach response")).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingProposal) { ReviewView(store: store) }
    }
}

struct OptionalCoachReviewsView: View {
    let store: PhoneStore
    @State private var launching = false
    @State private var showingProposal = false
    @State private var launchMessage: String?
    @Environment(\.openURL) private var openURL
    var body: some View {
        LiftList {
            Section {
                if let launchMessage { Text(launchMessage).font(.caption) }
                Text(L10n.s("ChatGPT is optional and separate. Sharing uses your chosen chat; Shortcuts does not inherit it. Local reviews remain available if the model fails.")).font(.caption).foregroundStyle(.secondary)
                NavigationLink(L10n.s("Optional ChatGPT setup")) { ShortcutHelpView() }
                Button(store.state.reviewNotificationsEnabled == true ? L10n.s("Turn off review notifications") : L10n.s("Enable review notifications")) {
                    Task { await store.enableReviewNotifications(store.state.reviewNotificationsEnabled != true) }
                }
            }
            ForEach(store.state.reviewQueue.reversed()) { job in
                Section(store.state.effectiveSessions.first(where: { $0.id == job.id })?.plan.title ?? L10n.s("Workout")) {
                    Text(L10n.key("review." + job.status.rawValue))
                    if job.outdatedAt != nil { Text(L10n.s("Evidence changed · request an updated response")).font(.caption) }
                    if let detail = job.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    if let session = store.state.effectiveSessions.first(where: { $0.id == job.id }) {
                        if job.result != nil { NavigationLink(L10n.s("Saved coach response")) { WorkoutEvidenceReviewView(session: session, store: store) } }
                        ShareLink(item: session.report()) { Text(L10n.s("Share report to my existing chat")) }
                    }
                    if job.status != .received || job.outdatedAt != nil {
                        Button(L10n.s("Run review Shortcut")) {
                            do { try store.selectReview(job.id); runShortcut() } catch { store.error = error.localizedDescription }
                        }.disabled(store.state.reviewQueue.contains(where: { $0.status == .running }) || launching)
                        if job.status == .running {
                            Button(L10n.s("Cancel this review")) { do { try store.endReview(job.id, cancelled: true, detail: L10n.s("Cancelled by user. Delayed results will be rejected.")) } catch { store.error = error.localizedDescription } }
                            Button(L10n.s("Allow retry")) { do { try store.endReview(job.id, cancelled: false, detail: L10n.s("Model or Shortcut did not return a result. Retry explicitly.")) } catch { store.error = error.localizedDescription } }
                        }
                    }
                }
            }
            if store.state.review != nil { Button(L10n.s("Review proposed workout")) { showingProposal = true } }
            if store.state.reviewQueue.isEmpty { Text(L10n.s("Completed workouts appear here after syncing from Watch.")) }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle(L10n.s("Workout reviews")).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingProposal) { ReviewView(store: store) }
            .task {
                while !Task.isCancelled {
                    store.refreshReviewStatus()
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                }
            }
    }
    private func runShortcut() {
        var parts = URLComponents(); parts.scheme = "shortcuts"; parts.host = "run-shortcut"
        parts.queryItems = [URLQueryItem(name: "name", value: "Little Lift Review")]
        if let url = parts.url {
            launching = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                launching = false
            }
            openURL(url) { accepted in launchMessage = accepted ? L10n.s("Opened Shortcuts to continue. Analysis is confirmed only when a result returns.") : L10n.s("Shortcuts could not open. Check setup and retry.") }
        }
    }
}
