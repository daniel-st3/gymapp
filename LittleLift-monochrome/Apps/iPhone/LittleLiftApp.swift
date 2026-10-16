import SwiftUI

@main
struct LittleLiftApp: App {
    @State private var store = PhoneStore.shared
    var body: some Scene {
        WindowGroup {
            PhoneRootView(store: store)
                .font(.callout)
                .disclosureGroupStyle(LiftDisclosureStyle())
                .tint(LiftStyle.accent)
                .preferredColorScheme(.dark)
                .modifier(LiftAccessibilityDiagnostics())
                .environment(\.locale, Locale(identifier: store.state.comfort?.language ?? Locale.current.identifier))
                .id(store.state.comfort?.language)
        }
    }
}
