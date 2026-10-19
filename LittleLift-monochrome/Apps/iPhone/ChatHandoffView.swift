import SwiftUI

/// Explicit clipboard handoff. No chat is read, messaged or marked delivered.
struct ChatHandoffView: View {
    let store: PhoneStore
    @State private var request = ""
    @State private var copiedMessage: String?
    @State private var notice: String?
    @State private var error: String?
    @State private var importSource: ChatImportSource?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LiftPageHeading(title: L10n.s("Keep your gym chat up to date"), detail: L10n.s("Copy one message into your existing chat. Bring its reply back here to review and use the workout."))
                LiftSurface {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(status).font(.subheadline)
                        if let packet = store.state.chatHandoff {
                            Text(packet.preparedAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(L10n.s("Copying is not sending. Little Lift cannot read the chat or confirm delivery to it.")).font(.caption).foregroundStyle(.secondary)
                    }.padding(18)
                }
                LiftSection(title: L10n.s("1 · Message for your chat")) {
                    TextField(L10n.s("Optional: today is legs, I have 45 minutes…"), text: $request, axis: .vertical)
                        .lineLimit(2...4).padding(16).background(LiftStyle.surface, in: .rect(cornerRadius: 16))
                        .accessibilityLabel(L10n.s("What to ask your coach"))
                    Text(L10n.s("Includes the saved plan, allowed recent history and the exact reply format. Profile and equipment follow your sharing preferences.")).font(.caption).foregroundStyle(.secondary)
                    NavigationLink(L10n.s("Choose what to include")) { CoachContextView(store: store) }.frame(minHeight: 44)
                    Button { copyMessage() } label: {
                        Label(L10n.s("Copy updated message"), systemImage: "doc.on.doc")
                    }.buttonStyle(QuietButtonStyle(prominent: true)).accessibilityIdentifier("chat.copy")
                    Button {
                        openURL(URL(string: "https://chatgpt.com/")!) { accepted in
                            notice = accepted ? L10n.s("Choose your existing gym chat and paste the copied message there.") : L10n.s("ChatGPT could not open. Open it yourself and paste the copied message in your gym chat.")
                        }
                    } label: { Label(L10n.s("Open ChatGPT"), systemImage: "arrow.up.forward.app") }
                        .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("chat.open")
                    if let notice { Text(notice).font(.subheadline).accessibilityIdentifier("chat.notice") }
                    if let copiedMessage {
                        DisclosureGroup(L10n.s("See the copied message")) {
                            Text(copiedMessage).font(.caption).textSelection(.enabled)
                        }
                    }
                }
                LiftSection(title: L10n.s("2 · Bring the reply back")) {
                    Text(L10n.s("Copy ChatGPT’s whole code block. Paste below; review the exercises before accepting. This does not replace a workout automatically.")).font(.subheadline).foregroundStyle(.secondary)
                    PasteButton(payloadType: String.self) { values in
                        importSource = ChatImportSource(text: values.joined(separator: "\n"))
                    }.labelStyle(.titleAndIcon).accessibilityIdentifier("chat.paste")
                    Button(L10n.s("Use text, screenshot or file")) { importSource = ChatImportSource(text: "") }.frame(minHeight: 44)
                }
                Text(L10n.s("After your workout reaches iPhone History, return here and copy a fresh message. New records make the context status change; sending to the chat remains your choice.")).font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.scrollDismissesKeyboard(.interactively).buttonStyle(.plain).background(.black).navigationTitle(L10n.s("My gym chat")).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $importSource) { source in SmartImportView(store: store, initialText: source.text) }
            .alert(L10n.s("Needs attention"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(L10n.s("OK")) { error = nil }
            } message: { Text(error ?? "") }
    }
    private var status: String {
        guard let packet = store.state.chatHandoff else { return L10n.s("Ready to prepare your first message") }
        if store.state.chatHasNewContext { return L10n.s("New app data · copy an updated message") }
        return packet.acceptedAt == nil ? L10n.s("Message copied · waiting for a reply you paste") : L10n.s("Reply accepted · workout saved in Little Lift")
    }
    private func copyMessage() {
        do {
            let packet = try store.prepareChatHandoff(request: request)
            UIPasteboard.general.string = packet.prompt
            copiedMessage = packet.prompt
            notice = L10n.s("Copied. Open your existing gym chat and paste this message.")
        } catch { self.error = error.localizedDescription }
    }
}

private struct ChatImportSource: Identifiable {
    let id = UUID()
    let text: String
}
