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
                Text(store.state.todayReceivedOnWatch ? L10n.s("Open Little Lift on Watch and tap Start workout.") : L10n.s("Waiting for the Watch to confirm this workout. Your plan is safe on this iPhone."))
                    .font(.caption).foregroundStyle(.secondary)
                if !store.state.todayReceivedOnWatch { Text(store.syncMessage).font(.caption).accessibilityIdentifier("today.syncResult") }
                DisclosureGroup(L10n.s("Connection & retry")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let receipt = store.state.lastWatchReceipt, store.state.todayReceivedOnWatch {
                            Text(receipt.receivedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                        }
                        Text(L10n.s("If a different workout is already open without logged sets, Watch offers to switch. Recorded work always stays with its original plan.")).font(.caption).foregroundStyle(.secondary)
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
