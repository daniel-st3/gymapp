import SwiftUI

struct ReviewQueueView: View {
    let store: PhoneStore
    @State private var openedAt: Date?
    @State private var launchMessage: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        LiftList {
            Section {
                if let launchMessage { Text(launchMessage).font(.caption) }
                Text(L10n.s("Share a report with your gym chat, or use your configured review Shortcut. You always review a proposed workout before accepting it.")).font(.caption).foregroundStyle(.secondary)
                NavigationLink(L10n.s("Shortcut and notification setup")) { ShortcutHelpView() }
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
        }.scrollContentBackground(.hidden).background(.black).navigationTitle(L10n.s("Coach reviews")).navigationBarTitleDisplayMode(.inline)
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
