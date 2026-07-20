import SwiftUI
import WebKit

/// In-app browser for importing straight from lcr.churchofjesuschrist.org:
/// the user signs in with their Church account (the session persists in the
/// web view's cookie store), opens one of the two reports, and Extract reads
/// the data directly — no PDF round trip, no font corruption.
struct LCRWebImportView: View {
    @Environment(WardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Report: String, CaseIterable, Identifiable {
        case memberList = "Member List"
        case wardCallings = "Ward Callings"
        var id: String { rawValue }
    }

    static let defaultMemberListURL =
        "https://lcr.churchofjesuschrist.org/mlt/report/create-a-report/custom-reports-details/bac4fcae-2d11-4df8-bf2f-541a3ba4f16f"
    static let defaultWardCallingsURL = "https://lcr.churchofjesuschrist.org/mlt/orgs?lang=eng"

    // Report URLs are editable in case LCR moves them.
    @AppStorage("lcrMemberListURL") private var memberListURL = LCRWebImportView.defaultMemberListURL
    @AppStorage("lcrWardCallingsURL") private var wardCallingsURL = LCRWebImportView.defaultWardCallingsURL

    @State private var report: Report = .memberList
    @State private var webView = WKWebView(frame: .zero, configuration: {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()  // persist the login session
        return configuration
    }())
    @State private var pendingImport: PendingImport?
    @State private var statusMessage: String?
    @State private var snapshotCopied = false
    @State private var extracting = false
    @State private var editingURLs = false

    private var currentURLString: String {
        report == .memberList ? memberListURL : wardCallingsURL
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Report", selection: $report) {
                    ForEach(Report.allCases) { report in
                        Text(report.rawValue).tag(report)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .onChange(of: report) {
                    loadCurrentReport()
                }

                WebViewRepresentable(webView: webView)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Fetch from LCR")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if webView.url == nil { loadCurrentReport() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button {
                            editingURLs = true
                        } label: {
                            Label("Edit Report URLs…", systemImage: "link")
                        }
                        Button {
                            copySnapshot()
                        } label: {
                            Label("Copy Page Snapshot", systemImage: "doc.on.doc")
                        }
                        Button {
                            loadCurrentReport()
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        Button(role: .destructive) {
                            signOutAndReset()
                        } label: {
                            Label("Sign Out & Reset", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    Button {
                        extract()
                    } label: {
                        if extracting {
                            ProgressView()
                        } else {
                            Label("Extract", systemImage: "square.and.arrow.down")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .disabled(extracting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
            }
            .sheet(item: $pendingImport) { pending in
                ImportPreviewView(pending: pending)
            }
            .alert("Snapshot Copied", isPresented: $snapshotCopied) {
                Button("OK") {}
            } message: {
                Text("A structural outline of the page (no member data) is on the clipboard — paste it into the chat so the importer can be adapted.")
            }
            .sheet(isPresented: $editingURLs) {
                urlEditor
            }
        }
    }

    private var urlEditor: some View {
        NavigationStack {
            Form {
                Section("Member List report URL") {
                    TextField("URL", text: $memberListURL, axis: .vertical)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("Ward Callings page URL") {
                    TextField("URL", text: $wardCallingsURL, axis: .vertical)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Button("Reset to Defaults") {
                        memberListURL = Self.defaultMemberListURL
                        wardCallingsURL = Self.defaultWardCallingsURL
                    }
                } footer: {
                    Text("Paste new URLs here if the reports move in LCR.")
                }
            }
            .navigationTitle("Report URLs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        editingURLs = false
                        loadCurrentReport()
                    }
                }
            }
        }
    }

    private func loadCurrentReport() {
        statusMessage = nil
        if let url = URL(string: currentURLString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            webView.load(URLRequest(url: url))
        } else {
            statusMessage = "That report URL isn't valid — check it under ••• → Edit Report URLs."
        }
    }

    private func extract() {
        extracting = true
        statusMessage = nil
        webView.evaluateJavaScript(LCRWebExtractor.scrapeScript) { result, error in
            defer { extracting = false }
            guard let json = result as? String else {
                statusMessage = "Couldn't read the page: \(error?.localizedDescription ?? "unknown error")"
                return
            }
            do {
                let table = try LCRWebExtractor.decodeScrape(json)
                switch report {
                case .memberList:
                    let members = try LCRWebExtractor.parseMembers(from: table)
                    guard members.count > 10 else {
                        statusMessage = "Only \(members.count) members found — is the full report loaded? Scroll it once, then Extract again."
                        return
                    }
                    let (newData, summary) = ImportReconciler.applyRoster(members, to: store.data)
                    pendingImport = PendingImport(
                        kind: .memberList,
                        fileName: "LCR Member List (\(members.count) members)",
                        newData: newData,
                        summary: summary
                    )
                case .wardCallings:
                    let parsed = try LCRWebExtractor.parseCallings(from: table)
                    let (newData, summary) = ImportReconciler.applyCallings(parsed, to: store.data)
                    pendingImport = PendingImport(
                        kind: .wardCallings,
                        fileName: "LCR Ward Callings (\(parsed.rows.count) callings)",
                        newData: newData,
                        summary: summary
                    )
                }
            } catch {
                statusMessage = error.localizedDescription
                    + " If this page looks right, use ••• → Copy Page Snapshot and share it."
            }
        }
    }

    private func copySnapshot() {
        webView.evaluateJavaScript(LCRWebExtractor.snapshotScript) { result, error in
            if let json = result as? String {
                UIPasteboard.general.string = json
                snapshotCopied = true
            } else {
                statusMessage = "Snapshot failed: \(error?.localizedDescription ?? "the page returned nothing")"
            }
        }
    }

    /// Clears the web view's cookies and site data so the user can sign in
    /// fresh — the LCR web app sometimes hangs on a half-restored session.
    private func signOutAndReset() {
        statusMessage = nil
        let store = WKWebsiteDataStore.default()
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {
            loadCurrentReport()
        }
    }
}

private struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
