import SwiftUI

struct ReviewQueueView: View {
    let store: PhoneStore
    var body: some View {
        LiftList {
            Section(L10n.s("Automatic reviews")) {
                Text(L10n.s("Every saved workout has a local review. No setup, account or connection is needed.")).font(.caption).foregroundStyle(.secondary)
                ForEach(store.state.sessions) { session in
                    NavigationLink { WorkoutEvidenceReviewView(session: session, store: store) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.plan.title)
                            Text(session.startedAt, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if store.state.sessions.isEmpty { Text(L10n.s("Completed workouts appear here after syncing from Watch.")) }
            NavigationLink(L10n.s("Optional ChatGPT setup")) { OptionalCoachReviewsView(store: store) }
        }.navigationTitle(L10n.s("Workout reviews")).navigationBarTitleDisplayMode(.inline)
    }
}

struct OptionalCoachReviewsView: View {
    let store: PhoneStore
    @State private var openedAt: Date?
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
                Section(store.state.sessions.first(where: { $0.id == job.id })?.plan.title ?? L10n.s("Workout")) {
                    Text(L10n.key("review." + job.status.rawValue))
                    if let detail = job.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    if let session = store.state.sessions.first(where: { $0.id == job.id }) {
                        ShareLink(item: session.report()) { Text(L10n.s("Share report to my existing chat")) }
                    }
                    if job.status != .received {
                        Button(L10n.s("Run review Shortcut")) {
                            do { try store.selectReview(job.id); runShortcut() } catch { store.error = error.localizedDescription }
                        }.disabled(job.status == .running || store.state.review != nil || (openedAt.map { Date().timeIntervalSince($0) < 3 } ?? false))
                        if job.status == .running {
                            Button(L10n.s("Cancel this review")) { do { try store.endReview(job.id, cancelled: true, detail: L10n.s("Cancelled by user. Delayed results will be rejected.")) } catch { store.error = error.localizedDescription } }
                            Button(L10n.s("Allow retry")) { do { try store.endReview(job.id, cancelled: false, detail: L10n.s("Model or Shortcut did not return a result. Retry explicitly.")) } catch { store.error = error.localizedDescription } }
                        }
                    }
                }
            }
            if store.state.review != nil { NavigationLink(L10n.s("Review proposed workout")) { ReviewView(store: store) } }
            if store.state.reviewQueue.isEmpty { Text(L10n.s("Completed workouts appear here after syncing from Watch.")) }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle(L10n.s("Workout reviews")).navigationBarTitleDisplayMode(.inline)
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
            openedAt = Date()
            openURL(url) { accepted in launchMessage = accepted ? L10n.s("Opened Shortcuts to continue. Analysis is confirmed only when a result returns.") : L10n.s("Shortcuts could not open. Check setup and retry.") }
        }
    }
}
