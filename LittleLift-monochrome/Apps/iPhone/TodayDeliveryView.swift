import SwiftUI

struct TodayDeliveryView: View {
    let store: PhoneStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationLink { WatchDeliveryDetailView(store: store) } label: {
            HStack(spacing: 12) {
                Image(systemName: store.state.todayReceivedOnWatch ? "checkmark.circle" : "applewatch")
                    .font(.title3.weight(.light)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.state.todayReceivedOnWatch ? L10n.s("Ready on Watch") : L10n.s("Waiting for Watch"))
                        .font(.subheadline).accessibilityIdentifier("today.delivery").contentTransition(.opacity)
                    Text(store.state.todayReceivedOnWatch ? L10n.s("Open Little Lift there and tap Start.") : L10n.s("Saved here. Tap to check delivery."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8); LiftChevron()
            }.frame(minHeight: 52).contentShape(.rect)
        }.animation(reduceMotion ? nil : LiftMotion.feedback, value: store.state.todayReceivedOnWatch)
    }
}

struct WatchDeliveryDetailView: View {
    let store: PhoneStore
    var body: some View {
        LiftList {
            Section {
                Label(store.state.todayReceivedOnWatch ? L10n.s("Received on Watch") : L10n.s("Saved on iPhone"),
                    systemImage: store.state.todayReceivedOnWatch ? "checkmark.circle" : "iphone")
                Text(store.syncMessage).font(.callout).textSelection(.enabled).accessibilityIdentifier("today.syncResult")
                Button(store.isSyncing ? L10n.s("Syncing…") : L10n.s("Check Watch delivery")) { store.sendToWatch() }
                    .disabled(store.isSyncing)
                if let receipt = store.state.lastWatchReceipt, store.state.todayReceivedOnWatch {
                    Text(receipt.receivedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
            } footer: { Text(L10n.s("Open Little Lift on Watch and tap Start workout.")) }
            Section {
                Text(L10n.s("If a different workout is already open without logged sets, Watch offers to switch. Recorded work always stays with its original plan."))
                Text(L10n.s("A receipt confirms the saved plan, not a live connection or a completed session. Finished workouts appear in History after the phone saves them."))
            }.font(.caption).foregroundStyle(.secondary)
        }.scrollContentBackground(.hidden).background(.black)
            .navigationTitle(L10n.s("Watch delivery")).navigationBarTitleDisplayMode(.inline)
    }
}
