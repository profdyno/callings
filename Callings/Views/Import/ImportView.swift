import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Import page: pick the two LCR PDFs (from Files or the app's Documents/import
/// folder, which is visible in the Files app) and apply after a preview.
struct ImportView: View {
    @Environment(WardStore.self) private var store
    @Environment(SyncService.self) private var syncService
    @State private var showingFilePicker = false
    @State private var pendingImport: PendingImport?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Ward organization") {
                        Text(store.data.lastCallingsImport?.formatted(date: .abbreviated, time: .shortened) ?? "Never imported")
                    }
                    LabeledContent("Member roster") {
                        Text(store.data.lastRosterImport?.formatted(date: .abbreviated, time: .shortened) ?? "Never imported")
                    }
                    LabeledContent("Members", value: "\(store.data.members.filter(\.isActiveOnRoster).count)")
                    LabeledContent("Callings", value: "\(store.data.callingSlots.count)")
                } header: {
                    Text("Current Data")
                }

                if syncService.canImport {
                    Section {
                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("Choose PDF…", systemImage: "folder")
                        }

                        ForEach(importFolderPDFs(), id: \.self) { url in
                            Button {
                                load(url: url, needsSecurityScope: false)
                            } label: {
                                Label(url.lastPathComponent, systemImage: "doc.richtext")
                            }
                        }
                    } header: {
                        Text("Import")
                    } footer: {
                        Text("Save the \"Ward Callings\" and \"Member List for Callings\" PDFs from lcr.churchofjesuschrist.org, then pick them here or drop them into this app's import folder in the Files app. The file type is detected automatically.")
                    }
                } else {
                    Section {
                        Label("Imports are done by the ward owner", systemImage: "lock")
                            .foregroundStyle(.secondary)
                    }
                }

                let placeholders = store.data.members.filter(\.isPlaceholder)
                if !placeholders.isEmpty {
                    Section {
                        ForEach(placeholders) { member in
                            VStack(alignment: .leading, spacing: 1) {
                                Label(member.name, systemImage: "person.crop.circle.badge.questionmark")
                                let callings = store.slots(heldBy: member.id)
                                    .compactMap { store.definition(for: $0)?.name }
                                if !callings.isEmpty {
                                    Text(callings.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 28)
                                }
                            }
                        }
                    } header: {
                        Text("Calling Holders Not on the Roster")
                    } footer: {
                        Text("These names from the Ward Callings import didn't match anyone in the member list — often out-of-unit callings, or a name spelled differently between the two reports.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf]) { result in
                if case .success(let url) = result {
                    load(url: url, needsSecurityScope: true)
                }
            }
            .sheet(item: $pendingImport) { pending in
                ImportPreviewView(pending: pending)
            }
        }
    }

    // MARK: - Loading

    private func load(url: URL, needsSecurityScope: Bool) {
        errorMessage = nil
        if needsSecurityScope {
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Could not access the selected file."
                return
            }
        }
        defer {
            if needsSecurityScope { url.stopAccessingSecurityScopedResource() }
        }

        // Keep a copy in Documents/import so the file stays available.
        let local = copyToImportFolder(url) ?? url
        guard let document = PDFDocument(url: local) else {
            errorMessage = "Could not open \(url.lastPathComponent) as a PDF."
            return
        }
        guard let pageText = document.page(at: 0)?.string else {
            errorMessage = "\(url.lastPathComponent) contains no readable text."
            return
        }

        if pageText.contains("Organizations and Callings") {
            let parsed = WardCallingsParser.parse(document: document)
            let (newData, summary) = ImportReconciler.applyCallings(parsed, to: store.data)
            pendingImport = PendingImport(kind: .wardCallings, fileName: url.lastPathComponent, newData: newData, summary: summary)
        } else if pageText.contains("Member List") {
            let parsed = MemberListParser.parse(document: document)
            var (newData, summary) = ImportReconciler.applyRoster(parsed.members, to: store.data)
            if let expected = parsed.expectedCount, expected != parsed.members.count {
                summary.countMismatches.append("Report says \(expected) members, parsed \(parsed.members.count)")
            }
            pendingImport = PendingImport(kind: .memberList, fileName: url.lastPathComponent, newData: newData, summary: summary)
        } else {
            errorMessage = "\(url.lastPathComponent) doesn't look like an LCR Ward Callings or Member List export."
        }
    }

    // MARK: - Documents/import folder

    private static var importFolderURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("import", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func importFolderPDFs() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.importFolderURL,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "pdf" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func copyToImportFolder(_ url: URL) -> URL? {
        let destination = Self.importFolderURL.appendingPathComponent(url.lastPathComponent)
        guard destination != url else { return destination }
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

/// A parsed import waiting for the user to confirm in the preview sheet.
struct PendingImport: Identifiable {
    enum Kind {
        case wardCallings
        case memberList
    }

    let id = UUID()
    let kind: Kind
    let fileName: String
    let newData: WardData
    let summary: ImportSummary
}
