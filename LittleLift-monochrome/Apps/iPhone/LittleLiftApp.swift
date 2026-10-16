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
        }
    }
}
