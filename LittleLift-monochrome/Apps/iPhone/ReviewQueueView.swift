import SwiftUI

struct ReviewQueueView: View {
    let store: PhoneStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        LiftList {
            Section {
                Text("Share a report with your gym chat, or use your configured review Shortcut. You always review a proposed workout before accepting it.").font(.caption).foregroundStyle(.secondary)
                NavigationLink("Shortcut and notification setup") { ShortcutHelpView() }
                Button(store.state.reviewNotificationsEnabled == true ? "Turn off review notifications" : "Enable review notifications") {
                    Task { await store.enableReviewNotifications(store.state.reviewNotificationsEnabled != true) }
                }
            }
            ForEach(store.state.reviewQueue.reversed()) { job in
                Section(store.state.sessions.first(where: { $0.id == job.id })?.plan.title ?? "Workout") {
                    Text(job.status.rawValue.capitalized)
                    if let detail = job.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    if let session = store.state.sessions.first(where: { $0.id == job.id }) {
                        ShareLink(item: session.report()) { Text("Share report to my existing chat") }
                    }
                    if job.status != .received {
                        Button("Run review Shortcut") {
                            do { try store.selectReview(job.id); runShortcut() } catch { store.error = error.localizedDescription }
                        }.disabled(job.status == .running || store.state.review != nil)
                        if job.status == .running {
                            Button("Cancel this review") { do { try store.endReview(job.id, cancelled: true, detail: "Cancelled by user. Delayed results will be rejected.") } catch { store.error = error.localizedDescription } }
                            Button("Allow retry") { do { try store.endReview(job.id, cancelled: false, detail: "Model or Shortcut did not return a result. Retry explicitly.") } catch { store.error = error.localizedDescription } }
                        }
                    }
                }
            }
            if store.state.review != nil { NavigationLink("Review proposed workout") { ReviewView(store: store) } }
            if store.state.reviewQueue.isEmpty { Text("Completed workouts appear here after syncing from Watch.") }
        }.scrollContentBackground(.hidden).background(.black).navigationTitle("Coach reviews").navigationBarTitleDisplayMode(.inline)
    }
    private func runShortcut() {
        var parts = URLComponents(); parts.scheme = "shortcuts"; parts.host = "run-shortcut"
        parts.queryItems = [URLQueryItem(name: "name", value: "Little Lift Review")]
        if let url = parts.url { openURL(url) }
    }
}
