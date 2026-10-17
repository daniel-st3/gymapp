import SwiftUI

struct TodayDeliveryView: View {
    let store: PhoneStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        LiftSurface {
            VStack(alignment: .leading, spacing: 10) {
                Label(store.state.todayReceivedOnWatch ? L10n.s("Received on Watch") : L10n.s("Saved on iPhone"),
                      systemImage: store.state.todayReceivedOnWatch ? "checkmark.circle" : "iphone")
                    .font(.subheadline).accessibilityIdentifier("today.delivery")
                    .contentTransition(.opacity)
                if store.state.todayReceivedOnWatch, let receipt = store.state.lastWatchReceipt {
                    Text(L10n.s("Receipt confirmed: \(receipt.receivedAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Locale(identifier: L10n.language))))")).font(.caption).foregroundStyle(.secondary)
                    Text(L10n.s("Ready to start on Watch. An active workout keeps its original plan.")).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L10n.s("Waiting for the Watch to confirm this workout. Your plan is safe on this iPhone.")).font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup(L10n.s("Connection & retry")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.syncMessage).font(.caption).textSelection(.enabled)
                        Button(L10n.s("Check Watch delivery")) { store.sendToWatch() }
                            .disabled(store.isSyncing).frame(minHeight: 44)
                        Text(L10n.s("A receipt confirms the saved plan, not a live connection or a completed session. Finished workouts appear in History after the phone saves them.")).font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }.font(.caption)
            }.padding(18)
        }.animation(reduceMotion ? nil : LiftMotion.feedback, value: store.state.todayReceivedOnWatch)
    }
}
