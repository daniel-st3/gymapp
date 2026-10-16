import WidgetKit
import SwiftUI

struct LauncherEntry: TimelineEntry { let date: Date }
struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry { LauncherEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) { completion(LauncherEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) { completion(Timeline(entries: [LauncherEntry(date: .now)], policy: .never)) }
}
struct LauncherView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: Label("Little Lift", systemImage: "dumbbell")
            case .accessoryInline: Label("Little Lift", systemImage: "dumbbell")
            case .accessoryCircular:
                Image(systemName: "dumbbell").resizable().scaledToFit().padding(7)
                    .accessibilityLabel("Open Little Lift")
            default:
                Image(systemName: "dumbbell").font(.title2).widgetLabel("Lift")
                    .accessibilityLabel("Open Little Lift")
            }
        }.foregroundStyle(.white).containerBackground(.black, for: .widget)
            .widgetURL(URL(string: "littlelift://workout"))
    }
}
@main struct LittleLiftLauncher: Widget {
    let kind = "LittleLiftLauncher"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LauncherProvider()) { _ in LauncherView() }
            .configurationDisplayName("Little Lift")
            .description("Open your current workout. Logging stays inside the app.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
