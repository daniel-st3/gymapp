import SwiftUI

@main
struct LittleLiftWatchApp: App {
    @State private var store = WatchStore.shared
    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store).tint(LiftStyle.accent).preferredColorScheme(.dark)
                .watchText(.body)
                .modifier(LiftAccessibilityDiagnostics())
        }
    }
}
