import SwiftUI

@main
struct LittleLiftWatchApp: App {
    @WKApplicationDelegateAdaptor(WorkoutApplicationDelegate.self) private var extensionDelegate
    @State private var store = WatchStore.shared
    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store).tint(LiftStyle.accent).preferredColorScheme(.dark)
                .watchText(.body)
                .modifier(LiftAccessibilityDiagnostics())
                .environment(\.locale, Locale(identifier: store.state.comfort?.language ?? Locale.current.identifier))
                .id(store.state.comfort?.language)
        }
    }
}
