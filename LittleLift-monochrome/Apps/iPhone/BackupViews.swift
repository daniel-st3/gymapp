import SwiftUI
import UniformTypeIdentifiers

struct WorkoutBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= WorkoutBackup.maximumBytes else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct WorkoutBackupView: View {
    let store: PhoneStore
    private let initialBackup: WorkoutBackup?
    init(store: PhoneStore, initialBackup: WorkoutBackup? = nil) { self.store = store; self.initialBackup = initialBackup }
    @State private var exporting = false
    @State private var importing = false
    @State private var document: WorkoutBackupDocument?
    @State private var backup: WorkoutBackup?
    @State private var preview: BackupRestorePreview?
    @State private var preferences = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        LiftList {
            if backup == nil { Section {
                Text(L10n.s("Keep a copy you control")).font(LiftType.heading)
                DisclosureGroup(L10n.s("Included data")) {
                    Text(L10n.s("Workouts, original records, corrections, routines, schedule, profile and saved coach responses. Choose where to save the file.")).font(.caption)
                }
                Text(L10n.s("The file contains personal training data. Experimental motion recordings and Apple permissions are not included.")).font(.caption).foregroundStyle(.secondary)
                Button {
                    do {
                        document = WorkoutBackupDocument(data: try WorkoutBackup(state: store.state).encoded())
                        exporting = true; error = nil; message = nil
                    } catch { self.error = error.localizedDescription }
                } label: { Label(L10n.s("Export backup"), systemImage: "square.and.arrow.up") }
                    .disabled(store.storageBlocked).accessibilityIdentifier("backup.export")
                Button { importing = true; error = nil; message = nil } label: {
                    Label(L10n.s("Choose backup to restore"), systemImage: "square.and.arrow.down")
                }.disabled(store.storageBlocked && !store.canRecoverFromBackup).accessibilityIdentifier("backup.choose")
            }
            }
            if let message { Section { Label(message, systemImage: "checkmark.circle") } }
            if let error { Section { Text(error).foregroundStyle(.secondary).textSelection(.enabled) } }
            if store.storageBlocked {
                Section {
                    Text(store.canRecoverFromBackup ? L10n.s("Your current file could not be read. Recovery uses the selected backup and keeps the unreadable file separately. Records missing from the backup cannot be merged automatically.") : L10n.s("Update Little Lift to read this storage version. Recovery cannot replace a newer format."))
                        .font(.callout)
                }
            }
            if let backup {
                Section(L10n.s("Review before restoring")) {
                    Text(backup.createdAt, format: .dateTime.day().month().year().hour().minute())
                    Text(L10n.s("Adds missing records and preserves current ones. Today stays unchanged; the archived plan goes to Routines.")).font(.callout)
                    Toggle(L10n.s("Also restore profile, schedule and preferences"), isOn: $preferences)
                    if preferences {
                        Text(L10n.s("Replaces your profile, equipment notes, weekly schedule, weekly goal, language and Watch control preferences. Sharing permissions and motion opt-in stay unchanged.")).font(.caption)
                        Text(backup.state.profile.isEmpty ? L10n.s("Profile in backup: empty") : String(backup.state.profile.prefix(600))).font(.caption).textSelection(.enabled)
                        Text(L10n.s("Scheduled days in backup: \(backup.state.weeklySchedule.count)")).font(.caption)
                    }
                }
            }
            if let preview {
                Section(L10n.s("What will be added")) {
                    MetricRow(title: L10n.s("Recorded workouts"), value: "\(preview.workoutsAdded)")
                    MetricRow(title: L10n.s("Routines"), value: "\(preview.routinesAdded)")
                    MetricRow(title: L10n.s("Imported records"), value: "\(preview.importedAdded)")
                    MetricRow(title: L10n.s("Corrections"), value: "\(preview.correctionsAdded)")
                    Text(L10n.s("\(preview.unchanged) existing records already match.")).font(.caption)
                    if !preview.conflicts.isEmpty {
                        DisclosureGroup(L10n.s("\(preview.conflicts.count) conflicts · keeping current records")) {
                            ForEach(preview.conflicts, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                        }
                    }
                    DisclosureGroup(L10n.s("How restoration works")) {
                        Text(L10n.s("Saved responses remain available. Restoring never starts ChatGPT or accepts a proposal. A local copy of your current data is saved first.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if backup != nil {
                Button(L10n.s("Refresh preview")) { refreshPreview() }
            }
        }.scrollContentBackground(.hidden).background(.black).presentationBackground(.black)
            .safeAreaInset(edge: .bottom) {
                if let preview {
                    VStack(spacing: 4) {
                        Button(L10n.s("Restore reviewed backup")) {
                            do {
                                try store.restoreBackup(preview)
                                self.backup = nil; self.preview = nil
                                message = L10n.s("Backup restored. Your current workout is unchanged."); error = nil
                            } catch { self.error = error.localizedDescription; self.preview = nil }
                        }.buttonStyle(QuietButtonStyle(prominent: true)).accessibilityIdentifier("backup.restore")
                        Button(L10n.s("Cancel preview")) { backup = nil; self.preview = nil }.frame(minHeight: 44)
                    }.padding(.horizontal, 24).padding(.top, 12).background(.black)
                }
            }
            .navigationTitle(L10n.s("Backups")).navigationBarTitleDisplayMode(.inline)
            .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                          defaultFilename: "LittleLift-backup-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                switch result {
                case .success: message = L10n.s("Backup exported.")
                case .failure(let error): self.error = error.localizedDescription
                }
                document = nil
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(), scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    backup = try WorkoutBackup.decode(InputBoundary.read(url, maximumBytes: WorkoutBackup.maximumBytes))
                    preferences = false; refreshPreview()
                } catch { self.error = error.localizedDescription; backup = nil; preview = nil }
            }
            .task { if backup == nil, let initialBackup { backup = initialBackup; refreshPreview() } }
            .onChange(of: preferences) { refreshPreview() }
    }
    private func refreshPreview() {
        do {
            guard let backup else { return }
            preview = try BackupRestorePreview(backup: backup, current: store.state, includePreferences: preferences)
            error = nil
        } catch { preview = nil; self.error = error.localizedDescription }
    }
}
