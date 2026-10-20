import SwiftUI

/// Explicit clipboard handoff. No chat is read, messaged or marked delivered.
struct ChatHandoffView: View {
    let store: PhoneStore
    @State private var request = ""
    @State private var copiedMessage: String?
    @State private var notice: String?
    @State private var error: String?
    @State private var importSource: ChatImportSource?
    @AppStorage("littlelift.gymChatURL") private var conversationURL = ""
    @State private var editingChatLink = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(L10n.s("Two steps to keep your existing chat and Little Lift aligned.")).font(.subheadline).foregroundStyle(.secondary)
                LiftSection(title: L10n.s("1 · Message for your chat")) {
                    TextField(L10n.s("Optional: today is legs, I have 45 minutes…"), text: $request, axis: .vertical)
                        .lineLimit(2...4).padding(16).background(LiftStyle.surface, in: .rect(cornerRadius: 16))
                        .accessibilityLabel(L10n.s("What to ask your coach"))
                    Button { copyMessage() } label: {
                        Label(L10n.s("Copy updated message"), systemImage: "doc.on.doc")
                    }.buttonStyle(QuietButtonStyle(prominent: true)).accessibilityIdentifier("chat.copy")
                    if copiedMessage != nil || store.state.chatHandoff != nil { Button {
                        openChatApp()
                    } label: { Label(L10n.s("Open ChatGPT"), systemImage: "arrow.up.forward.app") }
                        .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("chat.open") }
                    if let notice { Text(notice).font(.subheadline).accessibilityIdentifier("chat.notice") }
                    if let copiedMessage {
                        DisclosureGroup(L10n.s("See the copied message")) {
                            Text(copiedMessage).font(.caption).textSelection(.enabled)
                        }
                    }
                }
                LiftSection(title: L10n.s("2 · Bring the reply back")) {
                    Text(L10n.s("Paste the workout reply. You’ll review it before accepting.")).font(.subheadline).foregroundStyle(.secondary)
                    PasteButton(payloadType: String.self) { values in
                        importSource = ChatImportSource(text: values.joined(separator: "\n"))
                    }.labelStyle(.titleAndIcon).accessibilityIdentifier("chat.paste")
                    Button(L10n.s("Use text, screenshot or file")) { importSource = ChatImportSource(text: "") }.frame(minHeight: 44)
                }
                Divider()
                Text(status).font(.caption).foregroundStyle(.secondary)
                Text(L10n.s("Copying is not sending. Little Lift cannot read the chat or confirm delivery to it.")).font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.scrollDismissesKeyboard(.interactively).buttonStyle(.plain).background(.black).navigationTitle(L10n.s("My gym chat")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L10n.s("My conversation link"), systemImage: "link") { editingChatLink = true }
                    NavigationLink(L10n.s("Choose what to include")) { CoachContextView(store: store) }
                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel(L10n.s("Chat options"))
            } }
            .sheet(item: $importSource) { source in SmartImportView(store: store, initialText: source.text) }
            .sheet(isPresented: $editingChatLink) { ChatDestinationView() }
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
    private func openChatApp() {
        do {
            let url = try ChatAppLink.destination(conversationURL)
            // OpenAI's official association lists /open-app and /c/*. Never
            // silently send the user to Safari when the app cannot handle it.
            UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
                notice = opened
                    ? (conversationURL.isEmpty ? L10n.s("ChatGPT opened. Choose your gym chat and paste the copied message.") : L10n.s("Your conversation link opened in ChatGPT. Paste the copied message there."))
                    : L10n.s("iOS could not open the ChatGPT app. Your message is copied; open ChatGPT from its icon and choose your gym chat.")
            }
        } catch { notice = error.localizedDescription }
    }
}

private struct ChatImportSource: Identifiable {
    let id = UUID()
    let text: String
}

private struct ChatDestinationView: View {
    @AppStorage("littlelift.gymChatURL") private var saved = ""
    @State private var draft = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            LiftForm {
                Section {
                    Text(L10n.s("Optional: save the private address of your gym conversation once. Without it, ChatGPT opens and you choose the chat."))
                    TextField("https://chatgpt.com/c/…", text: $draft)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel(L10n.s("Private conversation link"))
                    PasteButton(payloadType: String.self) { draft = $0.joined() }
                } footer: {
                    Text(L10n.s("Copy its address from your browser, not Share. This stays on this iPhone and gives Little Lift no access to your messages."))
                }
                if let error { Text(error).font(.footnote) }
                Button(L10n.s("Save")) {
                    do {
                        let url = try ChatAppLink.destination(draft)
                        saved = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : url.absoluteString
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            }.scrollContentBackground(.hidden).background(.black)
                .navigationTitle(L10n.s("My conversation link")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.s("Close")) { dismiss() } } }
                .onAppear { draft = saved }
        }.tint(.white).presentationBackground(.black)
    }
}
