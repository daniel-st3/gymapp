import SwiftUI

enum LiftStyle {
    static let accent = Color(white: 0.94)
    static let error = Color(white: 0.86)
    static let surface = Color(white: 0.075)
}

enum LiftMotion {
    static let feedback = Animation.easeOut(duration: 0.12)
    static let content = Animation.easeOut(duration: 0.18)
}

enum LiftType {
    static let title = Font.system(.title2, design: .serif, weight: .regular)
    static let heading = Font.system(.headline, design: .default, weight: .regular)
    static let number = Font.system(.title3, design: .rounded, weight: .light)
}

enum LiftCopy {
    static func workoutSummary(_ plan: WorkoutPlan) -> String {
        let exercises = plan.exercises.count
        return "\(exercises) \(exercises == 1 ? "exercise" : "exercises") · \(plan.totalSets) \(plan.totalSets == 1 ? "set" : "sets")"
    }
}

/// Apple SF Symbols, rendered by the OS. Fixed icon columns align menu text;
/// labels remain visible so the symbol never has to explain an action alone.
struct LiftLabel: View {
    let title: String
    let symbol: String
    let detail: String?
    @ScaledMetric(relativeTo: .callout) private var iconWidth: CGFloat = 22
    init(_ title: String, _ symbol: String, detail: String? = nil) {
        self.title = title; self.symbol = symbol; self.detail = detail
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).symbolRenderingMode(.monochrome)
                .imageScale(.medium).foregroundStyle(.secondary)
                .frame(width: iconWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 2)
    }
}

/// One expansion target with an explicit accessibility state. The expansion is
/// local to this group; changing workout data never animates the whole screen.
#if os(iOS)
struct LiftDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : LiftMotion.content) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.caption)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                }.frame(minHeight: 44).contentShape(.rect)
            }.buttonStyle(.plain)
                .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded {
                VStack(alignment: .leading, spacing: 12) { configuration.content }
                    .padding(.top, 8).padding(.bottom, 6)
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }.clipped()
    }
}
#endif

struct LiftCompletionMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        Image(systemName: "checkmark.circle")
            .symbolRenderingMode(.monochrome)
            .symbolEffect(.bounce, options: .speed(1.8), value: reduceMotion ? false : appeared)
            .accessibilityHidden(true)
            .onAppear { appeared = true }
    }
}

/// Reveals incoming content only. Actions remain immediately available and
/// outgoing workout controls are never kept alive by an exit transition.
struct LiftContentEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 4)
            .onAppear { withAnimation(reduceMotion ? nil : LiftMotion.content) { appeared = true } }
            .onDisappear { appeared = false }
    }
}

/// Opt-in, local simulator diagnostics. Never includes workout contents.
struct LiftAccessibilityDiagnostics: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .onChange(of: reduceMotion, initial: true) { report() }
            .onChange(of: typeSize) { report() }
    }

    private func report() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--littlelift-diagnostics") {
            print("LittleLift accessibility: reduceMotion=\(reduceMotion), dynamicTypeSize=\(typeSize)")
        }
        #endif
    }
}

struct QuietButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    #if os(watchOS)
    @ScaledMetric(relativeTo: .callout) private var labelSize: CGFloat = 15
    #else
    @ScaledMetric(relativeTo: .callout) private var labelSize: CGFloat = 16
    #endif
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: labelSize, weight: .regular, design: .default))
            .multilineTextAlignment(.center)
            .foregroundStyle(prominent ? Color.black : LiftStyle.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(prominent ? Color(white: configuration.isPressed ? 0.78 : 0.94) : (configuration.isPressed ? Color(white: 0.13) : LiftStyle.surface), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(configuration.isPressed ? 0.3 : 0.16), lineWidth: 0.5) }
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : LiftMotion.feedback, value: configuration.isPressed)
    }
}

/// Plain secondary actions retain a full touch target without a filled button.
struct QuietTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
            .opacity(!isEnabled ? 0.4 : (configuration.isPressed ? 0.6 : 1))
            .animation(reduceMotion ? nil : LiftMotion.feedback, value: configuration.isPressed)
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) { Text(title); Spacer(minLength: 12); Text(value).fontDesign(.rounded).monospacedDigit().multilineTextAlignment(.trailing) }
            .padding(.vertical, 9)
            .accessibilityElement(children: .combine)
    }
}
