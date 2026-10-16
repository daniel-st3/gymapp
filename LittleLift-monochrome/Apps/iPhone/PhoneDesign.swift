import SwiftUI

/// Shared surfaces for the native editors and secondary screens. These remain
/// Forms/Lists, preserving field focus, keyboard behavior and native reordering.
struct LiftForm<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Form { content.listRowBackground(LiftStyle.surface) }
            .font(.callout).listSectionSpacing(20)
            .environment(\.defaultMinListRowHeight, 52)
    }
}

struct LiftList<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        List { content.listRowBackground(LiftStyle.surface) }
            .font(.callout).listSectionSpacing(20)
            .environment(\.defaultMinListRowHeight, 52)
    }
}

/// The phone has room for expressive titles; controls and workout data keep
/// the system face. All three type roles follow the user's Dynamic Type size.
struct LiftPageHeading: View {
    let title: String
    var detail: String? = nil
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 32
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: size, weight: .regular, design: .default))
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LiftEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.medium)).tracking(1.5)
            .foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
    }
}

struct LiftSurface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LiftStyle.surface, in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.07), lineWidth: 0.5) }
    }
}

struct LiftMenuRow: View {
    let title: String
    let symbol: String
    var detail: String? = nil
    var disclosure = true
    @ScaledMetric(relativeTo: .callout) private var iconWidth: CGFloat = 24
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.body.weight(.light)).frame(width: iconWidth)
                .foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if disclosure { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true) }
        }.padding(18).frame(minHeight: 60).contentShape(.rect)
    }
}

struct LiftSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiftEyebrow(text: title)
            content
        }
    }
}

struct LiftStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(.title3, design: .rounded, weight: .light)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

struct LiftChevron: View {
    var body: some View { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true) }
}

struct LiftRootChrome: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationTitle(L10n.s("Little Lift")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) {
                Text(L10n.s("LITTLE LIFT")).font(.caption2.weight(.medium)).tracking(2.5)
                    .accessibilityLabel(L10n.s("Little Lift"))
            } }
    }
}

struct LiftExerciseRow: View {
    let exercise: ExercisePlan
    let unit: WeightUnit
    let number: Int
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(String(format: "%02d", number)).font(.caption.monospaced()).foregroundStyle(.secondary)
                .padding(.top, 3).frame(minWidth: 22)
            VStack(alignment: .leading, spacing: 10) {
                Text(exercise.name).font(.body).fixedSize(horizontal: false, vertical: true)
                prescription
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
    }
    private var prescription: some View {
        Text(exercise.prescription(unit: unit))
            .font(.subheadline.monospacedDigit())
    }
    private var rest: some View {
        Label(L10n.s("\(exercise.restSeconds)s"), systemImage: "timer").font(.caption).foregroundStyle(.secondary)
            .accessibilityLabel(L10n.s("\(exercise.restSeconds) seconds prescribed rest"))
    }
}
