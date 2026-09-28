import SwiftUI

struct BackupSettingsView: View {
    @Environment(ShellModel.self) private var model

    var body: some View {
        List {
            Section {
                Button("backup.create") { Task { await model.backup.create() } }
                    .disabled(model.backup.isWorking)

                if model.backup.isWorking {
                    ProgressView("backup.working")
                }
            } footer: {
                Text("backup.localFirstNotice")
            }

            Section("backup.available") {
                if model.backup.records.isEmpty {
                    Text("backup.none").foregroundStyle(.secondary)
                } else {
                    ForEach(model.backup.records) { record in
                        NavigationLink {
                            BackupRestoreView(record: record)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(record.createdAt, format: .dateTime)
                                Text(ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(model.backup.isWorking)
                    }
                }
            }
        }
        .navigationTitle("backup")
        .task { await model.backup.refresh() }
        .alert("backup.error", isPresented: errorBinding) {
            Button("ok") {}
        } message: {
            Text(model.backup.message ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.backup.message != nil }, set: { if !$0 { model.backup.message = nil } })
    }
}

private struct BackupRestoreView: View {
    @Environment(ShellModel.self) private var model
    @State private var confirmsReplace = false
    let record: BackupRecord

    var body: some View {
        List {
            Section {
                Button("backup.keepDevice") {
                    Task { await model.backup.restore(record, resolution: .keepDevice) }
                }
                .disabled(model.backup.isWorking)

                Button("backup.replaceDevice", role: .destructive) {
                    confirmsReplace = true
                }
                .disabled(model.backup.isWorking)

                if model.backup.isWorking {
                    ProgressView("backup.working")
                }
            } footer: {
                Text("backup.conflictNotice")
            }
        }
        .navigationTitle("backup.restore")
        .confirmationDialog(
            "backup.replaceConfirm.title",
            isPresented: $confirmsReplace,
            titleVisibility: .visible
        ) {
            Button("backup.replaceConfirm.action", role: .destructive) {
                Task { await model.backup.restore(record, resolution: .replaceDevice) }
            }
            Button("backup.cancel", role: .cancel) {}
        } message: {
            Text("backup.replaceConfirm.message")
        }
    }
}
