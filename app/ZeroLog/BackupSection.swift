import SwiftUI
import UniformTypeIdentifiers
import ZeroLogCore

/// Save a copy of everything, and put it back.
///
/// This is not a power-user feature. A build signed with a free Apple ID stops
/// working after seven days, and re-signing it usually takes the app's data
/// with it — so without this, a week of real training is lost to the signing
/// process rather than to anything the user did.
struct BackupSection: View {
    @Environment(AppModel.self) private var model
    @State private var showingImporter = false
    @State private var result: RestoreResult?

    private enum RestoreResult: Identifiable {
        case restored(workouts: Int)
        case failed(String)
        var id: String {
            switch self {
            case .restored(let n): return "ok\(n)"
            case .failed(let m): return "err\(m)"
            }
        }
    }

    var body: some View {
        Section {
            if let data = model.backupData() {
                ShareLink(item: BackupDocument(data: data),
                          preview: SharePreview("ZeroLog backup")) {
                    Label("Save a copy", systemImage: "square.and.arrow.up")
                        .font(.ui(17))
                        .foregroundStyle(Color.textPrimary)
                }
            }
            Button {
                showingImporter = true
            } label: {
                Label("Restore from a copy", systemImage: "square.and.arrow.down")
                    .font(.ui(17))
                    .foregroundStyle(Color.textPrimary)
            }
        } header: {
            SectionTitle("Your data")
        } footer: {
            Text("Email the file to yourself. If you ever reinstall ZeroLog, restoring it brings your workouts back. Restoring never deletes anything you have logged since.")
                .font(.ui(14))
                .foregroundStyle(Color.textTertiary)
        }
        .listRowBackground(Color.surface)
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.json]) { outcome in
            switch outcome {
            case .success(let url):
                // A file from the Files app lives outside our sandbox.
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let count = try model.restore(from: Data(contentsOf: url))
                    result = .restored(workouts: count)
                } catch BackupError.tooNew(let version) {
                    result = .failed("That copy was saved by a newer version of ZeroLog (v\(version)). Update the app, then restore it.")
                } catch BackupError.unreadable {
                    result = .failed("That file isn't a ZeroLog backup, so nothing was changed.")
                } catch {
                    result = .failed("The file couldn't be read, so nothing was changed.")
                }
            case .failure:
                result = .failed("The file couldn't be opened, so nothing was changed.")
            }
        }
        .alert(item: $result) { outcome in
            switch outcome {
            case .restored(let workouts):
                // States the resulting total rather than "Success", because the
                // number is what tells the user it actually worked.
                return Alert(title: Text("Restored"),
                             message: Text("Your history now holds \(workouts) workout\(workouts == 1 ? "" : "s")."),
                             dismissButton: .default(Text("OK")))
            case .failed(let message):
                // Every failure path says nothing was changed, because the real
                // fear when restoring is destroying what you still have.
                return Alert(title: Text("Not restored"),
                             message: Text(message),
                             dismissButton: .default(Text("OK")))
            }
        }
    }
}

/// Wraps the JSON so ShareLink offers a real file with a sensible name,
/// rather than a wall of text in a message body.
private struct BackupDocument: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName(Backup.suggestedName())
    }
}
